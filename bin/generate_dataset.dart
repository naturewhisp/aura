import 'dart:io';

void main(List<String> args) async {
  int runs = 5;
  int turns = 6;
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

  for (int i = 1; i <= runs; i++) {
    print("--------------------------------------------------");
    print(" RUN $i di $runs in corso...");
    print("--------------------------------------------------");
    
    final result = await Process.run('dart', ['run', 'bin/run_simulation.dart', '--mode=interactive', '--turns=$turns']);
    
    // Print the stdout summary of the run (we can extract the last few lines or print the whole output)
    final lines = result.stdout.toString().split('\n');
    final summaryLines = lines.where((line) => 
      line.contains('SUMMARY') || 
      line.contains('INTERATTIVA CONCLUSA') || 
      line.contains('Replay interattivo salvato')
    ).toList();
    
    if (summaryLines.isNotEmpty) {
      print("Esito della run $i:");
      for (var s in summaryLines) {
        print("  $s");
      }
    } else {
      print(result.stdout);
    }

    if (result.exitCode != 0) {
      print("[ERRORE] La run $i è fallita con exit code ${result.exitCode}");
      if (result.stderr.toString().trim().isNotEmpty) {
        print("Dettagli errore: ${result.stderr}");
      }
    }
  }

  stopwatch.stop();
  print("======================================================================");
  print(" Generazione completata in ${stopwatch.elapsed.inMinutes} minuti e ${stopwatch.elapsed.inSeconds % 60} secondi.");
  print(" Controlla la cartella 'spike/replays/' per i file generati.");
  print("======================================================================");
}
