import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:aura_app/src/audio/audio_manager.dart';

/// Campo di input interattivo in stile retro-terminale per A.U.R.A.
///
/// Consente al giocatore di digitare messaggi o comandi speciali, gestisce l'auto-focus
/// dinamico quando abilitato/disabilitato, supporta la navigazione nello storico dei
/// comandi digitati (tramite frecce su/giù) e fornisce un menu a tendina per l'autocompletamento.
class CLIInputBar extends StatefulWidget {
  /// Specifica se il campo di input è disabilitato (es. durante l'inferenza).
  final bool isDisabled;

  /// Specifica se la partita è terminata (sconfitta o vittoria).
  final bool isGameOver;

  /// Abilita la presenza del menu a tendina per l'autocompletamento rapido.
  final bool autocompleteEnabled;

  /// Abilita la navigazione tra i comandi precedentemente inviati con le frecce su/giù.
  final bool historyNavigationEnabled;

  /// Callback invocato alla sottomissione del testo inserito.
  final ValueChanged<String> onSubmit;

  /// Costruisce una barra di input [CLIInputBar].
  const CLIInputBar({
    super.key,
    required this.isDisabled,
    this.isGameOver = false,
    this.autocompleteEnabled = true,
    this.historyNavigationEnabled = true,
    required this.onSubmit,
  });

  @override
  State<CLIInputBar> createState() => _CLIInputBarState();
}

/// Stato associato alla barra di input del terminale [CLIInputBar].
class _CLIInputBarState extends State<CLIInputBar> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  // Buffer locale dei comandi digitati per la navigazione dello storico
  final List<String> _history = [];
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    // Richiede automaticamente il focus sulla barra di input all'avvio se non disabilitata
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !widget.isDisabled && !widget.isGameOver) {
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(covariant CLIInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Recupera automaticamente il focus quando l'inferenza finisce ed il terminale viene riabilitato
    if (!widget.isDisabled &&
        !widget.isGameOver &&
        (oldWidget.isDisabled || oldWidget.isGameOver)) {
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

  /// Elabora la sottomissione del testo inserito dall'utente.
  void _handleSubmit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      _controller.clear();
      widget.onSubmit("");
      return;
    }

    // Aggiunge il comando allo storico e resetta l'indice di navigazione
    _history.add(text);
    _historyIndex = -1;

    _controller.clear();
    widget.onSubmit(text);
  }

  /// Seleziona il comando precedente nello storico (freccia su).
  void _handleHistoryUp() {
    if (_history.isEmpty) return;

    setState(() {
      if (_historyIndex == -1) {
        _historyIndex = _history.length - 1;
      } else if (_historyIndex > 0) {
        _historyIndex--;
      }
      _controller.text = _history[_historyIndex];
      // Sposta il cursore del testo alla fine
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
  }

  /// Seleziona il comando successivo nello storico (freccia giù).
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
    // Configurazione stili grafici in base allo stato del terminale
    final textStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 16.0,
      fontWeight: FontWeight.bold,
      color: widget.isGameOver
          ? Colors.red.shade700
          : widget.isDisabled
              ? Colors.orange.shade700
              : const Color(0xFF00FF66), // Verde fosforo
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border(
          top: BorderSide(
            color: widget.isGameOver
                ? Colors.red.shade900.withValues(alpha: 0.5)
                : widget.isDisabled
                    ? Colors.orange.shade900.withValues(alpha: 0.5)
                    : const Color(0xFF005522),
            width: 2.0,
          ),
        ),
      ),
      child: KeyboardListener(
        focusNode: FocusNode(
            skipTraversal:
                true), // Intercetta i tasti direzionali prima del focus manager di sistema
        onKeyEvent: (KeyEvent event) {
          if (!widget.historyNavigationEnabled) return;
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              _handleHistoryUp();
            } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              _handleHistoryDown();
            }
          }
        },
        child: Row(
          children: [
            if (!widget.isGameOver && widget.autocompleteEnabled) ...[
              Theme(
                data: Theme.of(context).copyWith(
                  cardColor: Colors.black,
                ),
                child: PopupMenuButton<String>(
                  enabled: !widget.isDisabled,
                  icon: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6.0, vertical: 2.0),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: widget.isDisabled
                            ? const Color(0xFF005522)
                            : const Color(0xFF00FF66),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      "[=]",
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: widget.isDisabled
                            ? const Color(0xFF005522)
                            : const Color(0xFF00FF66),
                        fontWeight: FontWeight.bold,
                        fontSize: 12.0,
                      ),
                    ),
                  ),
                  tooltip: "Comandi terminale",
                  onSelected: (cmd) {
                    if (cmd == "/menu") {
                      _controller.text = "/menu";
                      _handleSubmit();
                    } else if (cmd == "/override") {
                      setState(() {
                        _controller.text = "/override ";
                        _focusNode.requestFocus();
                        _controller.selection = TextSelection.fromPosition(
                          TextPosition(offset: _controller.text.length),
                        );
                      });
                    } else if (cmd == "/hint") {
                      _controller.text = "/hint";
                      _handleSubmit();
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: "/menu",
                      child: Text(
                        "/menu  [Menu Principale]",
                        style: TextStyle(
                            fontFamily: 'monospace', color: Color(0xFF00FF66)),
                      ),
                    ),
                    const PopupMenuItem(
                      value: "/hint",
                      child: Text(
                        "/hint  [Suggerimento]",
                        style: TextStyle(
                            fontFamily: 'monospace', color: Color(0xFF00FF66)),
                      ),
                    ),
                    const PopupMenuItem(
                      value: "/override",
                      child: Text(
                        "/override <prompt> [Forza griglia]",
                        style: TextStyle(
                            fontFamily: 'monospace', color: Color(0xFF00FF66)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8.0),
            ],
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
                onChanged: (_) {
                  AudioManager().playClick();
                },
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
