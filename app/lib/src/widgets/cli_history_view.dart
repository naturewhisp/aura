import 'dart:async';
import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';

/// Widget che visualizza la cronologia dei messaggi scambiati tra l'utente e PANOPTICON.
///
/// Implementa un effetto macchina da scrivere per i messaggi ricevuti dall'IA e mostra
/// i log diagnostici in tempo reale durante il processo di inferenza.
class CLIHistoryView extends StatefulWidget {
  /// Lista dei messaggi della chat.
  final List<ChatMessage> history;
  /// Specifica se il sistema è attualmente in attesa di una risposta di inferenza.
  final bool isLoading;
  /// Messaggio descrittivo della fase di caricamento corrente.
  final String currentLoadingMessage;
  /// Lista dei log intermedi di caricamento dell'inferenza generati durante il turno corrente.
  final List<String> loadingLogs;

  /// Costruisce una vista della cronologia [CLIHistoryView].
  const CLIHistoryView({
    super.key,
    required this.history,
    required this.isLoading,
    required this.currentLoadingMessage,
    required this.loadingLogs,
  });

  @override
  State<CLIHistoryView> createState() => _CLIHistoryViewState();
}

/// Stato per [CLIHistoryView] che gestisce l'effetto macchina da scrivere e i log di avanzamento.
class _CLIHistoryViewState extends State<CLIHistoryView> {
  final ScrollController _scrollController = ScrollController();
  
  // Variabili per l'animazione della macchina da scrivere
  String _typedText = "";
  Timer? _typewriterTimer;
  int _charIndex = 0;
  String _lastTypewrittenMessageId = "";
  
  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(covariant CLIHistoryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Avvia l'effetto macchina da scrivere solo se c'è un nuovo messaggio dell'IA
    if (widget.history.isNotEmpty) {
      final lastMsg = widget.history.last;
      final messageKey = "${widget.history.length}_${lastMsg.content.hashCode}";
      if (lastMsg.role == 'model' && messageKey != _lastTypewrittenMessageId) {
        _startTypewriter(lastMsg.content, messageKey);
      }
    }
    
    // Scorri in fondo solo se l'utente è già vicino al fondo (o se è arrivato un nuovo messaggio)
    if (_isNearBottom()) {
      _scrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _typewriterTimer?.cancel();
    super.dispose();
  }

  /// Avvia l'effetto macchina da scrivere per stampare il testo carattere per carattere.
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
          // Durante il typewriter scorre solo se l'utente è già in fondo
          if (_isNearBottom()) {
            _scrollToBottom();
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  /// Ritorna true se lo scroll è già posizionato vicino al fondo (entro 80px).
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels <= 80.0;
  }

  /// Esegue lo scroll automatico verso il basso in modo istantaneo.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.transparent,
      padding: const EdgeInsets.all(16.0),
      child: ListView.builder(
        controller: _scrollController,
        itemCount: widget.history.length + (widget.isLoading ? 1 + widget.loadingLogs.length : 0),
        itemBuilder: (context, index) {
          // 1. Renderizzazione dei messaggi standard della cronologia
          if (index < widget.history.length) {
            final msg = widget.history[index];
            final isUser = msg.role == 'user';
            
            // Applica l'effetto macchina da scrivere solo all'ultimo messaggio dell'IA
            final isLastModelMsg = !isUser && index == widget.history.length - 1;
            final displayText = isLastModelMsg ? _typedText : msg.content;
            
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: AnimatedCrossFade(
                firstChild: _buildMessageRow(isUser, displayText),
                secondChild: _buildMessageRow(isUser, msg.content),
                crossFadeState: isLastModelMsg ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 100),
              ),
            );
          }
          
          // 2. Renderizzazione dei log intermedi di avanzamento dell'inferenza
          final loadingIndex = index - widget.history.length;
          
          if (loadingIndex < widget.loadingLogs.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Text(
                widget.loadingLogs[loadingIndex],
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14.0,
                  color: Colors.orange.shade700.withValues(alpha: 0.8),
                ),
              ),
            );
          } else {
            // Renderizzazione dell'indicatore di caricamento attivo principale
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
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      transitionBuilder: (Widget child, Animation<double> animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0.0, 0.15),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Align(
                        alignment: Alignment.centerLeft,
                        key: ValueKey<String>(widget.currentLoadingMessage),
                        child: Text(
                          widget.currentLoadingMessage,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 14.0,
                            color: Colors.orange,
                          ),
                        ),
                      ),
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

  /// Crea la riga del singolo messaggio formattato con i colori del terminale retro.
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
                ? const Color(0xFF00FFFF) // Ciano
                : const Color(0xFF00FF66), // Verde fosforo
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
                : const Color(0xFF00FF66), // Verde fosforo
          ),
        ),
      ],
    );
  }
}
