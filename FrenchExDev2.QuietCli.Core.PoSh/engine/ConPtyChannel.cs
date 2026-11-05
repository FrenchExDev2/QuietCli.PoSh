#nullable enable
namespace FrenchExDev2.QuietCli {
    using System;
    using System.Collections;
    using System.Collections.Generic;
    using System.ComponentModel;
    using System.Diagnostics;
    using System.IO;
    using System.Runtime.InteropServices;
    using System.Text;
    using System.Threading;
    using System.Threading.Tasks;
    using Microsoft.Win32.SafeHandles;

    // Windows console transport. No executable-specific behavior belongs here.
    /// <summary>Native con pty channel contract used by the isolated runtime.</summary>
    public sealed class ConPtyChannel : IProcessChannel, ITerminalChannel {
        /// <summary>ConPTY instances always own a resizable terminal.</summary>
        public bool SupportsResize => true;
        /// <summary>Native coord contract used by the isolated runtime.</summary>
        [StructLayout(LayoutKind.Sequential)] struct Coord {
/// <summary>Native x, y contract used by the isolated runtime.</summary>
public short X, Y; }
        /// <summary>Native startup info contract used by the isolated runtime.</summary>
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct StartupInfo {
            /// <summary>Native size contract used by the isolated runtime.</summary>
            public int Size;
/// <summary>Native reserved, desktop, title contract used by the isolated runtime.</summary>
public string? Reserved, Desktop, Title;
/// <summary>Native x, y, xsize, ysize, xcount, ycount, fill, flags contract used by the isolated runtime.</summary>
public int X, Y, XSize, YSize, XCount, YCount, Fill, Flags;
            /// <summary>Native show, reserved size contract used by the isolated runtime.</summary>
            public short Show, ReservedSize;
/// <summary>Native reserved bytes, input, output, error contract used by the isolated runtime.</summary>
public IntPtr ReservedBytes, Input, Output, Error;
        }
        /// <summary>Native startup info ex contract used by the isolated runtime.</summary>
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] struct StartupInfoEx {
/// <summary>Native info contract used by the isolated runtime.</summary>
public StartupInfo Info;
/// <summary>Native attributes contract used by the isolated runtime.</summary>
public IntPtr Attributes; }
        /// <summary>Native process info contract used by the isolated runtime.</summary>
        [StructLayout(LayoutKind.Sequential)] struct ProcessInfo {
/// <summary>Native process, thread contract used by the isolated runtime.</summary>
public IntPtr Process, Thread;
/// <summary>Native process id, thread id contract used by the isolated runtime.</summary>
public int ProcessId, ThreadId; }
        /// <summary>Native create pipe contract used by the isolated runtime.</summary>
/// <param name="read">read for this native operation.</param>
/// <param name="write">write for this native operation.</param>
/// <param name="attributes">attributes for this native operation.</param>
/// <param name="size">size for this native operation.</param>
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool CreatePipe(out IntPtr read, out IntPtr write, IntPtr attributes, uint size);
        /// <summary>Native create pseudo console contract used by the isolated runtime.</summary>
/// <param name="size">size for this native operation.</param>
/// <param name="input">input for this native operation.</param>
/// <param name="output">output for this native operation.</param>
/// <param name="flags">flags for this native operation.</param>
/// <param name="console">console for this native operation.</param>
        [DllImport("kernel32.dll")] static extern int CreatePseudoConsole(Coord size, IntPtr input, IntPtr output, uint flags, out IntPtr console);
        /// <summary>Native resize pseudo console contract used by the isolated runtime.</summary>
/// <param name="console">console for this native operation.</param>
/// <param name="size">size for this native operation.</param>
        [DllImport("kernel32.dll")] static extern int ResizePseudoConsole(IntPtr console, Coord size);
        /// <summary>Native close pseudo console contract used by the isolated runtime.</summary>
/// <param name="console">console for this native operation.</param>
        [DllImport("kernel32.dll")] static extern void ClosePseudoConsole(IntPtr console);
        /// <summary>Native initialize proc thread attribute list contract used by the isolated runtime.</summary>
/// <param name="list">list for this native operation.</param>
/// <param name="count">count for this native operation.</param>
/// <param name="flags">flags for this native operation.</param>
/// <param name="size">size for this native operation.</param>
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
        /// <summary>Native update proc thread attribute contract used by the isolated runtime.</summary>
/// <param name="list">list for this native operation.</param>
/// <param name="flags">flags for this native operation.</param>
/// <param name="attribute">attribute for this native operation.</param>
/// <param name="value">value for this native operation.</param>
/// <param name="size">size for this native operation.</param>
/// <param name="previous">previous for this native operation.</param>
/// <param name="returned">returned for this native operation.</param>
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool UpdateProcThreadAttribute(IntPtr list, uint flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returned);
        /// <summary>Native delete proc thread attribute list contract used by the isolated runtime.</summary>
/// <param name="list">list for this native operation.</param>
        [DllImport("kernel32.dll")] static extern void DeleteProcThreadAttributeList(IntPtr list);
        /// <summary>Native create process w contract used by the isolated runtime.</summary>
/// <param name="app">app for this native operation.</param>
/// <param name="command">command for this native operation.</param>
/// <param name="processAttributes">process Attributes for this native operation.</param>
/// <param name="threadAttributes">thread Attributes for this native operation.</param>
/// <param name="inherit">inherit for this native operation.</param>
/// <param name="flags">flags for this native operation.</param>
/// <param name="environment">Environment overrides for this child only.</param>
/// <param name="directory">Native working directory.</param>
/// <param name="startup">startup for this native operation.</param>
/// <param name="info">info for this native operation.</param>
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessW(string? app, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, string directory, ref StartupInfoEx startup, out ProcessInfo info);
        /// <summary>Native close handle contract used by the isolated runtime.</summary>
/// <param name="handle">handle for this native operation.</param>
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        /// <summary>Native input, output contract used by the isolated runtime.</summary>
        readonly FileStream input, output;
        /// <summary>Native process contract used by the isolated runtime.</summary>
        readonly Process process;
        /// <summary>Native console contract used by the isolated runtime.</summary>
        IntPtr console;
        /// <summary>Native closed console contract used by the isolated runtime.</summary>
        int closedConsole;
        /// <summary>Checks a native API return value and raises its error.</summary>
/// <param name="success">Native API success flag.</param>
        static void Check(bool success) { if (!success) throw new Win32Exception(Marshal.GetLastWin32Error()); }
        /// <summary>Quotes one CreateProcessW argument without invoking a shell.</summary>
/// <param name="argument">One argument to quote for CreateProcessW.</param>
        static string Quote(string argument) {
            if (argument.Length != 0 && argument.IndexOfAny(new[] { ' ', '\t', '\n', '"' }) < 0) return argument;
            var result = new StringBuilder("\""); int slashes = 0;
            foreach (char value in argument) {
                if (value == '\\') { slashes++; continue; }
                if (value == '"') { result.Append('\\', slashes * 2 + 1); result.Append(value); }
                else { result.Append('\\', slashes); result.Append(value); } slashes = 0;
            }
            result.Append('\\', slashes * 2); return result.Append('"').ToString();
        }
        /// <summary>Native con pty channel contract used by the isolated runtime.</summary>
/// <param name="executable">Resolved native executable path.</param>
/// <param name="arguments">Exact invocation arguments without shell expansion.</param>
/// <param name="directory">Native working directory.</param>
/// <param name="environment">Environment overrides for this child only.</param>
/// <param name="columns">Terminal width in columns.</param>
/// <param name="rows">Terminal height in rows.</param>
        public ConPtyChannel(string executable, string[] arguments, string directory, IDictionary environment, int columns, int rows) {
            if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
            IntPtr inRead = IntPtr.Zero, inWrite = IntPtr.Zero, outRead = IntPtr.Zero, outWrite = IntPtr.Zero, attributes = IntPtr.Zero, block = IntPtr.Zero;
            ProcessInfo info = default;
            try {
                Check(CreatePipe(out inRead, out inWrite, IntPtr.Zero, 0)); Check(CreatePipe(out outRead, out outWrite, IntPtr.Zero, 0));
                Marshal.ThrowExceptionForHR(CreatePseudoConsole(new Coord { X = (short)columns, Y = (short)rows }, inRead, outWrite, 0, out console));
                IntPtr size = IntPtr.Zero; InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size); attributes = Marshal.AllocHGlobal(size);
                Check(InitializeProcThreadAttributeList(attributes, 1, 0, ref size));
                Check(UpdateProcThreadAttribute(attributes, 0, new IntPtr(0x00020016), console, new IntPtr(IntPtr.Size), IntPtr.Zero, IntPtr.Zero));
                var variables = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                foreach (DictionaryEntry entry in Environment.GetEnvironmentVariables()) variables[(string)entry.Key] = (string)entry.Value!;
                foreach (DictionaryEntry entry in environment) { if (entry.Value is null) variables.Remove((string)entry.Key); else variables[(string)entry.Key] = Convert.ToString(entry.Value)!; }
                variables["QUIETCLI_TRACKING"] = "0"; variables["QUIETCLI_RECALL"] = "0";
                var text = new StringBuilder(); foreach (var entry in variables) text.Append(entry.Key).Append('=').Append(entry.Value).Append('\0'); text.Append('\0');
                block = Marshal.StringToHGlobalUni(text.ToString());
                var command = new StringBuilder(Quote(executable)); foreach (string argument in arguments) command.Append(' ').Append(Quote(argument));
                // Prevent Windows from duplicating the redirected host's standard handles
                // into the terminal child even when bInheritHandles is false.
                var startup = new StartupInfoEx { Info = new StartupInfo { Size = Marshal.SizeOf<StartupInfoEx>(), Flags = 0x100 }, Attributes = attributes };
                Check(CreateProcessW(executable, command, IntPtr.Zero, IntPtr.Zero, false, 0x00080000 | 0x00000400, block, directory, ref startup, out info));
                process = Process.GetProcessById(info.ProcessId);
                input = new FileStream(new SafeFileHandle(inWrite, true), FileAccess.Write, 4096, false); inWrite = IntPtr.Zero;
                output = new FileStream(new SafeFileHandle(outRead, true), FileAccess.Read, 4096, false); outRead = IntPtr.Zero;
            } catch { CloseConsole(); throw; }
            finally {
                if (attributes != IntPtr.Zero) { DeleteProcThreadAttributeList(attributes); Marshal.FreeHGlobal(attributes); }
                if (block != IntPtr.Zero) Marshal.FreeHGlobal(block);
                foreach (IntPtr handle in new[] { inRead, inWrite, outRead, outWrite, info.Process, info.Thread }) if (handle != IntPtr.Zero) CloseHandle(handle);
            }
        }
        /// <summary>Native child input stream.</summary>
        public Stream Input => input;
        /// <summary>Native child output stream.</summary>
        public Stream Output => output;
        /// <summary>Native error stream, or Stream.Null for a merged terminal.</summary>
        public Stream Error => Stream.Null;
        /// <summary>Identity of the owned native process.</summary>
        public int Id => process.Id;
        /// <summary>Whether the owned native child has exited.</summary>
        public bool HasExited => process.HasExited;
        /// <summary>Native exit code when known, otherwise null.</summary>
        public int? ExitCode => HasExited ? process.ExitCode : null;
        /// <summary>Native close console contract used by the isolated runtime.</summary>
        void CloseConsole() { if (Interlocked.Exchange(ref closedConsole, 1) == 0 && console != IntPtr.Zero) { ClosePseudoConsole(console); console = IntPtr.Zero; } }
        /// <summary>Native wait async contract used by the isolated runtime.</summary>
/// <param name="token">Cancellation requested by the owning operation.</param>
        public async Task WaitAsync(CancellationToken token) { await process.WaitForExitAsync(token).ConfigureAwait(false); CloseConsole(); }
        // A terminal has no pipe-style half-close. This sends an EOF keystroke hint.
        /// <summary>Native close input contract used by the isolated runtime.</summary>
        public void CloseInput() { input.WriteByte(4); input.Flush(); }
        /// <summary>Native resize contract used by the isolated runtime.</summary>
/// <param name="columns">Terminal width in columns.</param>
/// <param name="rows">Terminal height in rows.</param>
        public void Resize(int columns, int rows) { Marshal.ThrowExceptionForHR(ResizePseudoConsole(console, new Coord { X = (short)columns, Y = (short)rows })); }
        /// <summary>Terminates only the process tree owned by this transport.</summary>
        public void Kill() { try { process.Kill(true); } catch (InvalidOperationException) { } catch (Win32Exception) { } }
        /// <summary>Releases native handles owned by this component.</summary>
        public void Dispose() { CloseConsole(); input.Dispose(); output.Dispose(); process.Dispose(); }
    }
}
