import 'dart:convert';
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
    print("==================================================");
    print(" AVVIO RUN $i di $runs IN CORSO (Real-Time Output)");
    print("==================================================");
    
    final process = await Process.start('dart', ['run', 'bin/run_simulation.dart', '--mode=interactive', '--turns=$turns']);
    
    // Listen to stdout and stderr streams in real-time and write them to the console
    final stdoutSub = process.stdout.transform(utf8.decoder).listen((data) {
      stdout.write(data);
    });
    final stderrSub = process.stderr.transform(utf8.decoder).listen((data) {
      stderr.write(data);
    });
    
    final exitCode = await process.exitCode;
    
    // Ensure all output has been flushed before continuing
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
