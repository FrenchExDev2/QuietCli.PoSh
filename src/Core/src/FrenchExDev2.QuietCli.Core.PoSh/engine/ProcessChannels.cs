using System.Collections;
using System.Diagnostics;
using System.Text;
namespace FrenchExDev2.QuietCli {
    /// <summary>Native iprocess channel contract used by the isolated runtime.</summary>
    public interface IProcessChannel : IDisposable {
        /// <summary>Native child input stream.</summary>
        Stream Input { get; }
        /// <summary>Native child output stream.</summary>
        Stream Output { get; }
        /// <summary>Native error stream, or Stream.Null for a merged terminal.</summary>
        Stream Error { get; }
        /// <summary>Identity of the owned native process.</summary>
        int Id { get; }
        /// <summary>Native exit code when known, otherwise null.</summary>
        int? ExitCode { get; }
        /// <summary>Whether the owned native child has exited.</summary>
        bool HasExited { get; }
        /// <summary>Native wait async contract used by the isolated runtime.</summary>
/// <param name="token">Cancellation requested by the owning operation.</param>
        Task WaitAsync(CancellationToken token);
        /// <summary>Native close input contract used by the isolated runtime.</summary>
        void CloseInput();
        /// <summary>Terminates only the process tree owned by this transport.</summary>
        void Kill();
    }
    /// <summary>Optional capability for transports backed by a terminal.</summary>
    public interface ITerminalChannel {
        /// <summary>True only when this instance owns a terminal.</summary>
        bool SupportsResize { get; }
        /// <summary>Changes the terminal dimensions.</summary>
        /// <param name="columns">Validated width.</param>
        /// <param name="rows">Validated height.</param>
        void Resize(int columns, int rows);
    }
    /// <summary>Native pipe channel contract used by the isolated runtime.</summary>
    public sealed class PipeChannel : IProcessChannel, ITerminalChannel {
        /// <summary>Native process contract used by the isolated runtime.</summary>
        readonly Process process = new();
        /// <summary>Native pty contract used by the isolated runtime.</summary>
        readonly bool pty;
        /// <summary>Native control contract used by the isolated runtime.</summary>
        System.Net.Sockets.Socket? control;
        /// <summary>Native control lock contract used by the isolated runtime.</summary>
        readonly object controlLock = new();
        /// <summary>Initializes ownership before asynchronous process startup.</summary>
        /// <param name="pty">Whether the verified Unix bridge is requested.</param>
        private PipeChannel(bool pty) { this.pty = pty; }
        /// <summary>Starts the owned process and asynchronously establishes the optional terminal control socket.</summary>
        /// <param name="executable">Resolved executable path.</param>
        /// <param name="arguments">Native argument vector.</param>
        /// <param name="directory">Native working directory.</param>
        /// <param name="environment">Child-only environment overrides.</param>
        /// <param name="redirectInput">Whether stdin is redirected.</param>
        /// <param name="helper">Verified Unix bridge path, or empty for pipes.</param>
        /// <param name="columns">Initial terminal columns.</param>
        /// <param name="rows">Initial terminal rows.</param>
        /// <param name="token">Startup cancellation.</param>
        internal static async Task<PipeChannel> StartAsync(string executable, string[] arguments, string directory, IDictionary environment, bool redirectInput, string helper, int columns, int rows, CancellationToken token) {
            bool pty = helper.Length != 0;
            var channel = new PipeChannel(pty);
            var process = channel.process;
            System.Net.Sockets.Socket? listener = null; string? socketPath = null;
            var start = new ProcessStartInfo(pty ? helper : executable) { WorkingDirectory = directory, UseShellExecute = false,
                CreateNoWindow = true, RedirectStandardInput = redirectInput || pty, RedirectStandardOutput = true, RedirectStandardError = true };
            if (pty) {
                // A private directory keeps other local users from connecting to the control socket.
                socketPath = Path.Combine(PrivateDirectory.Create("quietcli-pty-"), "control.sock");
                listener = new(System.Net.Sockets.AddressFamily.Unix, System.Net.Sockets.SocketType.Stream, System.Net.Sockets.ProtocolType.Unspecified);
                listener.Bind(new System.Net.Sockets.UnixDomainSocketEndPoint(socketPath)); listener.Listen(1);
                foreach (string argument in new[] { "--control", socketPath, "--columns", columns.ToString(), "--rows", rows.ToString(), "--", executable }) start.ArgumentList.Add(argument);
            }
            foreach (string argument in arguments) start.ArgumentList.Add(argument);
            foreach (DictionaryEntry entry in environment) { if (entry.Value is null) start.Environment.Remove((string)entry.Key); else start.Environment[(string)entry.Key] = Convert.ToString(entry.Value); }
            start.Environment["QUIETCLI_TRACKING"] = "0"; start.Environment["QUIETCLI_RECALL"] = "0";
            process.StartInfo = start;
            try {
                process.Start();
                if (listener is not null) {
                    channel.control = await listener.AcceptAsync(token).AsTask().WaitAsync(TimeSpan.FromSeconds(10), token);
                    channel.control.ReceiveTimeout = 10000; channel.control.SendTimeout = 10000;
                }
                return channel;
            } catch { channel.Kill(); channel.Dispose(); throw;
            } finally {
                listener?.Dispose();
                if (socketPath is not null) { string socketDirectory = Path.GetDirectoryName(socketPath)!; if (File.Exists(socketPath)) File.Delete(socketPath); if (Directory.Exists(socketDirectory)) Directory.Delete(socketDirectory); }
            }
        }
        /// <summary>Native child input stream.</summary>
        public Stream Input => process.StandardInput.BaseStream;
        /// <summary>Native child output stream.</summary>
        public Stream Output => process.StandardOutput.BaseStream;
        /// <summary>Native error stream, or Stream.Null for a merged terminal.</summary>
        public Stream Error => process.StandardError.BaseStream;
        /// <summary>Identity of the owned native process.</summary>
        public int Id => process.Id;
        /// <summary>Whether the owned native child has exited.</summary>
        public bool HasExited => process.HasExited;
        /// <summary>Native exit code when known, otherwise null.</summary>
        public int? ExitCode => HasExited ? process.ExitCode : null;
        /// <summary>Only a bridge-backed instance can be resized.</summary>
        public bool SupportsResize => pty;
        /// <summary>Native wait async contract used by the isolated runtime.</summary>
/// <param name="token">Cancellation requested by the owning operation.</param>
        public Task WaitAsync(CancellationToken token) => process.WaitForExitAsync(token);
        // Closing this pipe preserves ordering with all prior writes. A separate
        // control message could overtake bytes still buffered before the PTY bridge.
        /// <summary>Native close input contract used by the isolated runtime.</summary>
        public void CloseInput() { process.StandardInput.Close(); }
        /// <summary>Native send control contract used by the isolated runtime.</summary>
/// <param name="kind">Metadata record kind.</param>
/// <param name="columns">Terminal width in columns.</param>
/// <param name="rows">Terminal height in rows.</param>
        void SendControl(byte kind, int columns, int rows) {
            byte[] packet = new byte[] { kind, (byte)(columns >> 8), (byte)columns, (byte)(rows >> 8), (byte)rows };
            if (control is null) return;
            lock (controlLock) {
                int offset = 0;
                while (offset < packet.Length) { int sent = control.Send(packet, offset, packet.Length - offset, System.Net.Sockets.SocketFlags.None); if (sent == 0) throw new IOException("PTY control channel closed."); offset += sent; }
                byte[] acknowledgement = new byte[1];
                if (control.Receive(acknowledgement) != 1 || acknowledgement[0] != 0) throw new IOException("PTY resize was not acknowledged.");
            }
        }
        /// <summary>Native resize contract used by the isolated runtime.</summary>
/// <param name="columns">Terminal width in columns.</param>
/// <param name="rows">Terminal height in rows.</param>
        public void Resize(int columns, int rows) { if (!pty) throw new InvalidOperationException("Resize requires a terminal."); SendControl(1, columns, rows); }
        /// <summary>Terminates only the process tree owned by this transport.</summary>
        public void Kill() { try { process.Kill(true); } catch (InvalidOperationException) { } catch (System.ComponentModel.Win32Exception) { } }
        /// <summary>Releases native handles owned by this component.</summary>
        public void Dispose() { control?.Dispose(); process.Dispose(); }
    }

}
