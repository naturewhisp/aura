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

  /// Flag che indica se lo scroll automatico è attivo.
  /// Disattivato quando l'utente scorre manualmente verso l'alto,
  /// riattivato quando l'utente torna vicino al fondo.
  bool _shouldAutoScroll = true;

  /// Flag per evitare che i jump programmati attivino/disattivino l'auto-scroll
  bool _isProgrammaticScroll = false;

  /// Lunghezza della storia al precedente aggiornamento per rilevare nuovi messaggi.
  int _previousHistoryLength = 0;

  @override
  void initState() {
    super.initState();
    _previousHistoryLength = widget.history.length;
    _scrollController.addListener(_onScrollChanged);
    // Al primo frame (incluso il resume di una partita salvata), scorri al fondo.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToBottom();
    });
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

    // Se è stato aggiunto un nuovo messaggio alla storia, forza lo scroll al fondo.
    if (widget.history.length > _previousHistoryLength) {
      _previousHistoryLength = widget.history.length;
      _shouldAutoScroll = true;
      _scheduleScrollToBottom();
    } else if (_shouldAutoScroll) {
      // Aggiornamenti di caricamento (carosello) -> scorri solo se l'utente è al fondo.
      _scheduleScrollToBottom();
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    _typewriterTimer?.cancel();
    super.dispose();
  }

  /// Listener sullo scroll: aggiorna il flag in base alla posizione dell'utente.
  void _onScrollChanged() {
    if (_isProgrammaticScroll) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // Tolleranza di 80px: se l'utente è entro 80px dal fondo, riattiva l'auto-scroll.
    final atBottom = (pos.maxScrollExtent - pos.pixels) <= 80.0;
    if (_shouldAutoScroll != atBottom) {
      setState(() {
        _shouldAutoScroll = atBottom;
      });
    }
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
        });
        if (_shouldAutoScroll) {
          _jumpToBottom();
        }
      } else {
        timer.cancel();
      }
    });
  }

  /// Pianifica uno scroll istantaneo al fondo dopo il layout del frame corrente.
  void _scheduleScrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_shouldAutoScroll) {
        _jumpToBottom();
      }
    });
  }

  /// Salta istantaneamente al fondo della lista.
  void _jumpToBottom() {
    if (_scrollController.hasClients) {
      _isProgrammaticScroll = true;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      // Rilascia dopo che la chiamata sincrona a jumpTo ha triggerato i listener
      _isProgrammaticScroll = false;
    }
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
