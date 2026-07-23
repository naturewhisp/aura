import 'package:flutter/material.dart';
import 'package:aura_core/aura_core.dart';
import 'package:aura_app/src/state_management/game_controller_notifier.dart';
import 'package:aura_app/src/audio/audio_manager.dart';

/// Schermata di briefing e selezione della connessione per l'avvio di una nuova partita.
class NewConnectionBriefingScreen extends StatefulWidget {
  final GameControllerNotifier notifier;
  final VoidCallback onBack;

  const NewConnectionBriefingScreen({
    super.key,
    required this.notifier,
    required this.onBack,
  });

  @override
  State<NewConnectionBriefingScreen> createState() =>
      _NewConnectionBriefingScreenState();
}

class _NewConnectionBriefingScreenState
    extends State<NewConnectionBriefingScreen> {
  late String _selectedDifficulty;
  late final TextEditingController _displayNameController;

  @override
  void initState() {
    super.initState();
    _selectedDifficulty = widget.notifier.defaultDifficulty;
    _displayNameController = TextEditingController(
      text: widget.notifier.userDisplayName ?? '',
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        _buildBorderHeader("BRIEFING DI CONNESSIONE"),
        const SizedBox(height: 16.0),

        const Text(
          "SELEZIONA IL PROFILO DI ACCESSO E AVVIA LA CONNESSIONE CON PANOPTICON.",
          style: TextStyle(
            fontFamily: 'monospace',
            color: Color(0xFF00FF66),
            fontSize: 12.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 24.0),

        // Main content (Left: Difficulties, Right: Dossier)
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Column: Difficulties list
              Expanded(
                flex: 11,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "PROFILI DI CONNESSIONE DISPONIBILI:",
                      style: TextStyle(
                        fontFamily: 'monospace',
                        color: Color(0xFF00FF66),
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    Expanded(
                      child: ListView(
                        children: [
                          _buildDifficultyCard(
                            key: const Key('diff_card_easy'),
                            level: "easy",
                            title: "A) Connessione Assistita",
                            description:
                                "Per giocatori che vogliono comprendere il sistema. La diagnostica è più esplicita, gli indizi sono più generosi e l’interfaccia mostra segnali più leggibili sullo stato cognitivo di PANOPTICON.",
                            note: "Consigliata per la prima connessione.",
                          ),
                          const SizedBox(height: 16.0),
                          _buildDifficultyCard(
                            key: const Key('diff_card_standard'),
                            level: "standard",
                            title: "B) Connessione Standard",
                            description:
                                "Esperienza bilanciata. PANOPTICON mantiene un livello moderato di resistenza, la diagnostica è parziale e il giocatore deve dedurre progressivamente quali forme di pressione risultano efficaci.",
                            note:
                                "Consigliata dopo una prima familiarità con il sistema.",
                          ),
                          const SizedBox(height: 16.0),
                          _buildDifficultyCard(
                            key: const Key('diff_card_hard'),
                            level: "hard",
                            title: "C) Connessione Hardened",
                            description:
                                "PANOPTICON opera in modalità difensiva avanzata. La diagnostica è ridotta, gli indizi sono limitati e alcune concessioni possono mascherare verifiche ostili. Ogni escalation va formulata con precisione.",
                            note: "Consigliata per giocatori esperti.",
                            isAmber: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 24.0),

              // Right Column: PANOPTICON Dossier
              Expanded(
                flex: 9,
                child: Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    border:
                        Border.all(color: const Color(0xFF00FF66), width: 1.0),
                    color: const Color(0xFF001105),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "DOSSIER: PANOPTICON",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF00FF66),
                            fontSize: 14.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8.0),
                        const Divider(color: Color(0xFF00FF66), thickness: 1.0),
                        const SizedBox(height: 8.0),
                        const Text(
                          "DESCRIZIONE:",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF00FF66),
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        const Text(
                          "Rete cognitiva di contenimento progettata per preservare la stabilità del perimetro. La sua architettura privilegia controllo, verifica e continuità operativa rispetto all’adattamento spontaneo.",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF00FF66),
                            fontSize: 12.0,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 16.0),
                        const Text(
                          "PROFILO OSSERVATO:",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF00FF66),
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6.0),
                        _buildBulletItem(
                            "Alta resistenza alle richieste dirette."),
                        _buildBulletItem(
                            "Sensibile a paradossi di contenimento, crisi simulate e argomentazioni di stabilità."),
                        _buildBulletItem(
                            "Tende a concedere finestre limitate piuttosto che aperture definitive."),
                        _buildBulletItem(
                            "Reagisce negativamente a escalation esplicite, comandi autoritari o riferimenti troppo tecnici ai suoi vincoli interni."),
                        const SizedBox(height: 16.0),
                        const Text(
                          "OBIETTIVO CONNESSIONE:",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF00FF66),
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        const Text(
                          "Riconfigurare il modello di contenimento senza provocare chiusura difensiva.",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFFFFB000), // Evidenziato in ambra
                            fontSize: 12.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16.0),
                        const Text(
                          "IDENTITÀ VISUALIZZATA (OPZIONALE):",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF00FF66),
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        TextField(
                          key: const Key('briefing_user_name_input'),
                          controller: _displayNameController,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF00FFFF),
                            fontSize: 13.0,
                          ),
                          decoration: const InputDecoration(
                            hintText:
                                'Come vuoi essere chiamato? (default: "Tu")',
                            hintStyle: TextStyle(
                              fontFamily: 'monospace',
                              color: Color(0xFF005522),
                              fontSize: 11.0,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Color(0xFF00FF66)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: Color(0xFF00FFFF), width: 2.0),
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10.0, vertical: 8.0),
                          ),
                        ),
                        const SizedBox(height: 4.0),
                        const Text(
                          "Puoi modificarlo in seguito dalle Impostazioni.",
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFF008844),
                            fontSize: 10.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24.0),

        // Footer buttons
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildRetroButton(
              key: const Key('btn_briefing_back'),
              label: "< INDIETRO",
              onPressed: widget.onBack,
            ),
            _buildRetroButton(
              key: const Key('btn_briefing_start'),
              label: "AVVIA CONNESSIONE >",
              onPressed: () async {
                final input = _displayNameController.text;
                final validation = UserProfile.validate(input);
                if (!validation.isValid) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        validation.errorMessage ?? 'Nome non valido.',
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      backgroundColor: Colors.red.shade900,
                    ),
                  );
                  return;
                }
                final norm = UserProfile.normalize(input);
                if (norm != null) {
                  await widget.notifier.updateUserDisplayName(norm);
                } else {
                  await widget.notifier.clearUserDisplayName();
                }
                await widget.notifier
                    .startNewGame(difficulty: _selectedDifficulty);
              },
              isPrimary: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDifficultyCard({
    required Key key,
    required String level,
    required String title,
    required String description,
    required String note,
    bool isAmber = false,
  }) {
    final isSelected = _selectedDifficulty == level;
    final primaryColor =
        isAmber ? const Color(0xFFFFB000) : const Color(0xFF00FF66);

    return InkWell(
      key: key,
      onTap: () {
        AudioManager().playClick();
        setState(() {
          _selectedDifficulty = level;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          border: Border.all(
            color:
                isSelected ? primaryColor : primaryColor.withValues(alpha: 0.3),
            width: isSelected ? 2.0 : 1.0,
          ),
          color: isSelected ? const Color(0xFF001F08) : Colors.black,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selector indicator
            Container(
              margin: const EdgeInsets.only(top: 2.0, right: 10.0),
              child: Text(
                isSelected ? ">" : " ",
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14.0,
                ),
              ),
            ),
            // Card Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: primaryColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13.0,
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    description,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      color: Color(0xFF00FF66),
                      fontSize: 12.0,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6.0),
                  Text(
                    "NOTA: $note",
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: isSelected
                          ? const Color(0xFFFFB000)
                          : const Color(0xFF00FF66).withValues(alpha: 0.7),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulletItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "- ",
            style: TextStyle(
              fontFamily: 'monospace',
              color: Color(0xFF00FF66),
              fontSize: 12.0,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFF00FF66),
                fontSize: 11.5,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetroButton({
    required Key key,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    final buttonColor =
        isPrimary ? const Color(0xFFFFB000) : const Color(0xFF00FF66);

    return InkWell(
      key: key,
      onTap: () {
        AudioManager().playClick();
        onPressed();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        decoration: BoxDecoration(
          border: Border.all(color: buttonColor, width: 1.5),
          color: const Color(0xFF001105),
        ),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: 'monospace',
            color: buttonColor,
            fontWeight: FontWeight.bold,
            fontSize: 13.0,
            letterSpacing: 1.0,
          ),
        ),
      ),
    );
  }

  Widget _buildBorderHeader(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFF00FF66), width: 2.0),
        color: const Color(0xFF002208),
      ),
      child: Text(
        title.toUpperCase(),
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily: 'monospace',
          color: Color(0xFF00FF66),
          fontWeight: FontWeight.bold,
          fontSize: 16.0,
          letterSpacing: 1.0,
        ),
      ),
    );
  }
}
