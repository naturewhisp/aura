import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  int runs = 5;
  int turns = 6;
  
  // Parsing degli argomenti da riga di comando per personalizzare il numero di esecuzioni e turni
  for (var arg in args) {
    if (arg.startsWith('--runs=')) {
      runs = int.tryParse(arg.split('=')[1]) ?? 5;
    } else if (arg.startsWith('--turns=')) {
      turns = int.tryParse(arg.split('=')[1]) ?? 6;
    }
  }

  print("======================================================================");
  print(" A.U.R.A. Dataset Generator (Telemetria per Fine-Tuning)");
  print("======================================================================");
  print("Avvio di $runs simulazioni interattive sequenziali...");
  print("I replay verranno salvati in: spike/replays/\n");

  final stopwatch = Stopwatch()..start();

  // Esegue sequenzialmente le simulazioni per raccogliere i dati di gioco (telemetria)
  for (int i = 1; i <= runs; i++) {
    print("==================================================");
    print(" AVVIO RUN $i di $runs IN CORSO (Real-Time Output)");
    print("==================================================");
    
    // Avvia la simulazione interattiva come processo Dart separato
    final process = await Process.start('dart', [
      'run', 
      'bin/run_simulation.dart', 
      '--mode=interactive', 
      '--turns=$turns'
    ]);
    
    // Ascolta e inoltra lo stdout e lo stderr del sotto-processo in tempo reale alla console principale
    final stdoutSub = process.stdout.transform(utf8.decoder).listen((data) {
      stdout.write(data);
    });
    final stderrSub = process.stderr.transform(utf8.decoder).listen((data) {
      stderr.write(data);
    });
    
    // Attende il completamento della simulazione corrente
    final exitCode = await process.exitCode;
    
    // Garantisce che tutti i flussi di output siano stati scritti sulla console prima di procedere alla run successiva
    await stdoutSub.asFuture();
    await stderrSub.asFuture();

    print("\n--------------------------------------------------");
    print(" RUN $i di $runs COMPLETATA con exit code $exitCode");
    print("--------------------------------------------------\n");
  }

  stopwatch.stop();
  print("======================================================================");
  print(" Generazione completata in ${stopwatch.elapsed.inMinutes} minuti e ${stopwatch.elapsed.inSeconds % 60} secondi.");
  print(" Controlla la cartella 'spike/replays/' per i file generati.");
  print("======================================================================");
}
