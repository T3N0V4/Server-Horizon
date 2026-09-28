using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

namespace Horizons.Panel
{
    public sealed class LogEntry
    {
        public readonly string Text;
        public readonly bool IsError;

        public LogEntry(string text, bool isError)
        {
            Text = text;
            IsError = isError;
        }
    }

    // All process callbacks run in managed C#, never in a PowerShell runspace.
    public sealed class ProcessBridge : IDisposable
    {
        private const int MaximumQueuedLines = 20000;
        private readonly object lifecycleGate = new object();
        private readonly object outputGate = new object();
        private readonly object queueGate = new object();
        private readonly ConcurrentQueue<LogEntry> queue = new ConcurrentQueue<LogEntry>();
        private Process process;
        private StreamWriter transcript;
        private StreamWriter inputWriter;
        private Thread stdoutRecovery;
        private Thread stderrRecovery;
        private int queuedLines;
        private long droppedLines;
        private int started;
        private int stdoutCompleted;
        private int stderrCompleted;
        private int lastExitCode;
        private bool startAttempted;
        private bool disposed;
        private bool transcriptFailed;

        public Process Process { get { return process; } }

        public bool HasExited
        {
            get
            {
                lock (lifecycleGate)
                {
                    return Volatile.Read(ref started) == 0 || disposed || process.HasExited;
                }
            }
        }

        public bool OutputCompleted
        {
            get
            {
                return HasExited && Volatile.Read(ref stdoutCompleted) != 0 &&
                    Volatile.Read(ref stderrCompleted) != 0;
            }
        }

        public int ExitCode
        {
            get
            {
                lock (lifecycleGate)
                {
                    if (Volatile.Read(ref started) == 0)
                        throw new InvalidOperationException("El proceso no fue iniciado.");
                    if (!disposed)
                    {
                        if (!process.HasExited)
                            throw new InvalidOperationException("El proceso todavia esta en ejecucion.");
                        lastExitCode = process.ExitCode;
                    }
                    return lastExitCode;
                }
            }
        }

        public bool IsQueueEmpty { get { return queue.IsEmpty; } }
        public long DroppedLines { get { return Interlocked.Read(ref droppedLines); } }

        public void Start(string executable, string arguments, string workingDirectory, string consoleLogPath)
        {
            lock (lifecycleGate)
            {
                if (disposed) throw new ObjectDisposedException("ProcessBridge");
                if (startAttempted)
                    throw new InvalidOperationException("Usa un ProcessBridge nuevo para cada inicio.");
                startAttempted = true;

                try
                {
                    transcript = new StreamWriter(new FileStream(consoleLogPath, FileMode.Append,
                        FileAccess.Write, FileShare.ReadWrite), new UTF8Encoding(false));
                    transcript.AutoFlush = true;
                    process = new Process();
                    process.StartInfo = new ProcessStartInfo
                    {
                        FileName = executable,
                        Arguments = arguments,
                        WorkingDirectory = workingDirectory,
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardInput = true,
                        RedirectStandardOutput = true,
                        RedirectStandardError = true,
                        StandardOutputEncoding = Encoding.UTF8,
                        StandardErrorEncoding = Encoding.UTF8
                    };
                    process.OutputDataReceived += OnOutput;
                    process.ErrorDataReceived += OnError;
                    if (!process.Start())
                        throw new InvalidOperationException("No se pudo crear el proceso del servidor.");
                    Volatile.Write(ref started, 1);
                }
                catch
                {
                    // No running process exists here. Cleanup must not hide the launch error.
                    if (process != null) process.Dispose();
                    process = null;
                    if (transcript != null)
                    {
                        try { transcript.Dispose(); } catch { }
                        transcript = null;
                    }
                    Volatile.Write(ref stdoutCompleted, 1);
                    Volatile.Write(ref stderrCompleted, 1);
                    throw;
                }

                // Once started, always retain the process so the UI can send stop.
                try
                {
                    inputWriter = new StreamWriter(process.StandardInput.BaseStream,
                        new UTF8Encoding(false), 1024, true);
                    inputWriter.AutoFlush = true;
                }
                catch (Exception error)
                {
                    Record("[PANEL] No se pudo abrir la entrada de comandos: " + error.Message, true);
                }
                try { process.BeginOutputReadLine(); }
                catch (Exception error) { RecoverReader(false, error); }
                try { process.BeginErrorReadLine(); }
                catch (Exception error) { RecoverReader(true, error); }
            }
        }

        private void OnOutput(object sender, DataReceivedEventArgs args)
        {
            if (args.Data == null) Volatile.Write(ref stdoutCompleted, 1);
            else Record(args.Data, false);
        }

        private void OnError(object sender, DataReceivedEventArgs args)
        {
            if (args.Data == null) Volatile.Write(ref stderrCompleted, 1);
            else Record(args.Data, true);
        }

        private void RecoverReader(bool isError, Exception startError)
        {
            Record("[PANEL] No se pudo iniciar la lectura asincrona de " +
                (isError ? "stderr" : "stdout") + ": " + startError.Message, true);
            // A failed Begin*ReadLine may still leave a usable synchronous reader.
            try
            {
                Thread reader = new Thread(delegate()
                {
                    try
                    {
                        StreamReader stream = isError ? process.StandardError : process.StandardOutput;
                        string line;
                        while ((line = stream.ReadLine()) != null) Record(line, isError);
                    }
                    catch (Exception error)
                    {
                        Record("[PANEL] Fallo la captura de " + (isError ? "stderr" : "stdout") +
                            ": " + error.Message + ". El proceso sigue bajo control del panel.", true);
                    }
                    finally
                    {
                        if (isError) Volatile.Write(ref stderrCompleted, 1);
                        else Volatile.Write(ref stdoutCompleted, 1);
                    }
                });
                reader.IsBackground = true;
                reader.Start();
                if (isError) stderrRecovery = reader;
                else stdoutRecovery = reader;
            }
            catch (Exception error)
            {
                Record("[PANEL] No se pudo recuperar la captura: " + error.Message, true);
                if (isError) Volatile.Write(ref stderrCompleted, 1);
                else Volatile.Write(ref stdoutCompleted, 1);
            }
        }

        private void Record(string text, bool isError)
        {
            lock (outputGate)
            {
                // A disk failure must never escape a DataReceived callback and crash the panel.
                if (transcript != null && !transcriptFailed)
                {
                    try { transcript.WriteLine(text); }
                    catch (Exception error)
                    {
                        transcriptFailed = true;
                        Enqueue(new LogEntry("[PANEL] No se pudo escribir el registro: " +
                            error.Message + ". La consola sigue recibiendo datos.", true));
                    }
                }
                Enqueue(new LogEntry(text, isError));
            }
        }

        private void Enqueue(LogEntry entry)
        {
            lock (queueGate)
            {
                queue.Enqueue(entry);
                queuedLines++;
                while (queuedLines > MaximumQueuedLines)
                {
                    LogEntry discarded;
                    if (!queue.TryDequeue(out discarded)) break;
                    queuedLines--;
                    Interlocked.Increment(ref droppedLines);
                }
            }
        }

        public LogEntry[] Drain(int maximum)
        {
            if (maximum < 1) return new LogEntry[0];
            List<LogEntry> entries = new List<LogEntry>(Math.Min(maximum, MaximumQueuedLines));
            lock (queueGate)
            {
                LogEntry entry;
                while (entries.Count < maximum && queue.TryDequeue(out entry))
                {
                    queuedLines--;
                    entries.Add(entry);
                }
            }
            return entries.ToArray();
        }

        public void Send(string command)
        {
            if (command == null) throw new ArgumentNullException("command");
            if (command.IndexOf('\r') >= 0 || command.IndexOf('\n') >= 0)
                throw new ArgumentException("Envia un solo comando por vez.", "command");
            lock (lifecycleGate)
            {
                if (disposed) throw new ObjectDisposedException("ProcessBridge");
                if (Volatile.Read(ref started) == 0 || process.HasExited)
                    throw new InvalidOperationException("El servidor no esta en ejecucion.");
                if (inputWriter == null)
                    throw new InvalidOperationException("La entrada de comandos no esta disponible.");
                inputWriter.WriteLine(command);
                inputWriter.Flush();
                Record("> " + command, false);
            }
        }

        public void Dispose()
        {
            lock (lifecycleGate)
            {
                if (disposed) return;
                if (Volatile.Read(ref started) != 0)
                {
                    if (!process.HasExited)
                        throw new InvalidOperationException("Envia stop y espera a que termine antes de cerrar el proceso.");
                    // Also waits for final asynchronous output callbacks after process exit.
                    process.WaitForExit();
                    if (stdoutRecovery != null) stdoutRecovery.Join();
                    if (stderrRecovery != null) stderrRecovery.Join();
                    lastExitCode = process.ExitCode;
                }
                if (process != null)
                {
                    if (inputWriter != null)
                    {
                        try { inputWriter.Dispose(); } catch { }
                        inputWriter = null;
                    }
                    process.OutputDataReceived -= OnOutput;
                    process.ErrorDataReceived -= OnError;
                    process.Dispose();
                }
                lock (outputGate)
                {
                    if (transcript != null)
                    {
                        try { transcript.Dispose(); }
                        catch (Exception error)
                        {
                            Enqueue(new LogEntry("[PANEL] No se pudo cerrar el registro: " + error.Message, true));
                        }
                        transcript = null;
                    }
                }
                disposed = true;
            }
        }
    }
}
