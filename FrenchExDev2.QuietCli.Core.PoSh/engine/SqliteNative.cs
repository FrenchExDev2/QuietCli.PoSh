#nullable disable
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace FrenchExDev2.QuietCli.Storage {
    // SQLite's stable C API. No CLI, NuGet download, or dependency on another module.
    // https://www.sqlite.org/c3ref/open.html
    // https://www.sqlite.org/c3ref/bind_blob.html
    /// <summary>Native sqlite contract used by the isolated runtime.</summary>
    internal static class Sqlite {
        /// <summary>Native library contract used by the isolated runtime.</summary>
        const string Library = "quietcli_sqlite";
        /// <summary>Installs the resolver for the native SQLite library.</summary>
        /// <remarks>One-time static assembly initialization; loads the binary only on the first native import.</remarks>
        static Sqlite() { NativeLibrary.SetDllImportResolver(typeof(Sqlite).Assembly, Resolve); }
        /// <summary>Resolves the SQLite alias to a bundled or system binary.</summary>
        /// <remarks>Tries Database.NativeDirectory first, then platform system names. Returns zero for another alias and throws DllNotFoundException if SQLite cannot be loaded.</remarks>
        /// <param name="name">Library alias requested by the .NET runtime.</param>
        /// <param name="assembly">Requesting assembly supplied by .NET; unused by this resolver.</param>
        /// <param name="path">Search policy supplied by .NET; unused by this resolver.</param>
        /// <returns>Native library handle, or IntPtr.Zero for another name.</returns>
        static IntPtr Resolve(string name, Assembly assembly, DllImportSearchPath? path) {
            if (name != Library) return IntPtr.Zero;
            string architecture = RuntimeInformation.ProcessArchitecture == Architecture.Arm64 ? "aarch64" : "x86_64";
            string[] candidates = OperatingSystem.IsWindows() ? new[] { Path.Combine(Environment.SystemDirectory, "winsqlite3.dll") } :
                OperatingSystem.IsMacOS() ? new[] { "/usr/lib/libsqlite3.dylib" } :
                new[] { "/usr/lib/" + architecture + "-linux-gnu/libsqlite3.so.0", "/lib/" + architecture + "-linux-gnu/libsqlite3.so.0", "/usr/lib/libsqlite3.so.0", "/lib/libsqlite3.so.0", "/usr/lib64/libsqlite3.so.0" };
            string bundled = Path.Combine(Database.NativeDirectory, OperatingSystem.IsWindows() ? "e_sqlite3.dll" : OperatingSystem.IsMacOS() ? "libe_sqlite3.dylib" : "libe_sqlite3.so");
            if (Path.IsPathFullyQualified(bundled) && File.Exists(bundled)) {
                if (NativeLibrary.TryLoad(bundled, out IntPtr bundledHandle)) return bundledHandle;
                throw new BadImageFormatException("BundledSQLiteInvalid");
            }
            foreach (string candidate in candidates)
                if (NativeLibrary.TryLoad(candidate, out IntPtr handle)) return handle;
            throw new DllNotFoundException("QuietCli requires the system SQLite library (winsqlite3 or libsqlite3).");
        }
        /// <summary>Opens a SQLite handle with the supplied flags.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="path">UTF-8 path to the SQLite file.</param>
        /// <param name="db">Connection handle returned as output.</param>
        /// <param name="flags">Native open flags.</param>
        /// <param name="vfs">Pointer to the VFS name; zero uses the default VFS.</param>
        /// <returns>SQLite code to check.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int sqlite3_open_v2([MarshalAs(UnmanagedType.LPUTF8Str)] string path, out IntPtr db, int flags, IntPtr vfs);
        /// <summary>Requests closure of a SQLite handle.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="db">Native connection handle to close.</param>
        /// <returns>SQLite close code.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_close_v2(IntPtr db);
        /// <summary>Reads the error message associated with a connection.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="db">Native handle associated with the error.</param>
        /// <returns>Native pointer to UTF-8 text read immediately by Database.Check.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern IntPtr sqlite3_errmsg(IntPtr db);
        /// <summary>Configures the busy timeout for a database.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="db">Native connection handle.</param>
        /// <param name="ms">Requested maximum timeout in milliseconds.</param>
        /// <returns>SQLite code to check.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_busy_timeout(IntPtr db, int ms);
        /// <summary>Compiles SQL text into a native statement.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="db">Native connection.</param>
        /// <param name="sql">Query encoded as UTF-8 by marshalling.</param>
        /// <param name="length">Native text length; -1 uses its NUL terminator.</param>
        /// <param name="statement">Statement handle returned as output.</param>
        /// <param name="tail">Output address for the remaining text; IntPtr.Zero ignores it here.</param>
        /// <returns>SQLite code to check.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)]
        internal static extern int sqlite3_prepare_v2(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql, int length, out IntPtr statement, IntPtr tail);
        /// <summary>Releases a prepared SQLite statement.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Statement handle to release.</param>
        /// <returns>SQLite finalization code.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_finalize(IntPtr statement);
        /// <summary>Advances a SQLite statement.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Prepared and bound statement to advance.</param>
        /// <returns>Native code; 100 indicates a row and 101 indicates completion in this adapter.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_step(IntPtr statement);
        /// <summary>Binds a SQL NULL value to a parameter.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Prepared statement.</param>
        /// <param name="index">One-based parameter index.</param>
        /// <returns>SQLite code to check.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_bind_null(IntPtr statement, int index);
        /// <summary>Binds a signed 64-bit integer to a parameter.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Prepared statement.</param>
        /// <param name="index">One-based parameter index.</param>
        /// <param name="value">Integer value to bind.</param>
        /// <returns>SQLite code to check.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_bind_int64(IntPtr statement, int index, long value);
        /// <summary>Binds a double-precision floating-point value to a parameter.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Prepared statement.</param>
        /// <param name="index">One-based parameter index.</param>
        /// <param name="value">Floating-point value to bind.</param>
        /// <returns>SQLite code to check.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_bind_double(IntPtr statement, int index, double value);
        /// <summary>Binds UTF-8 text to a SQL parameter.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Prepared statement.</param>
        /// <param name="index">One-based parameter index.</param>
        /// <param name="value">UTF-8 buffer containing the text and its terminator.</param>
        /// <param name="length">Text byte count, excluding the terminator.</param>
        /// <param name="destructor">Native ownership policy; the adapter uses -1 to request a copy.</param>
        /// <returns>SQLite code to check.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_bind_text(IntPtr statement, int index, byte[] value, int length, IntPtr destructor);
        /// <summary>Reads the number of columns in a statement.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Prepared statement.</param>
        /// <returns>Number of result columns.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_column_count(IntPtr statement);
        /// <summary>Reads the native name of a column.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Prepared statement.</param>
        /// <param name="column">Zero-based column index.</param>
        /// <returns>UTF-8 pointer immediately converted to a .NET string.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern IntPtr sqlite3_column_name(IntPtr statement, int column);
        /// <summary>Reads the SQLite type code of the current value.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Statement positioned on a row.</param>
        /// <param name="column">Zero-based column index.</param>
        /// <returns>Type code used to select the .NET conversion.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern int sqlite3_column_type(IntPtr statement, int column);
        /// <summary>Reads a column as a signed 64-bit integer.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Statement positioned on a row.</param>
        /// <param name="column">Zero-based column index.</param>
        /// <returns>Native integer value.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern long sqlite3_column_int64(IntPtr statement, int column);
        /// <summary>Reads a column as a double-precision floating-point value.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Statement positioned on a row.</param>
        /// <param name="column">Zero-based column index.</param>
        /// <returns>Native floating-point value.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern double sqlite3_column_double(IntPtr statement, int column);
        /// <summary>Reads a column as UTF-8 text.</summary>
        /// <remarks>Internal P/Invoke declaration for the SQLite C API; handles are owned by Database and no sqlite3 executable is launched.</remarks>
        /// <param name="statement">Statement positioned on a row.</param>
        /// <param name="column">Zero-based column index.</param>
        /// <returns>Native pointer immediately converted to a .NET string.</returns>
        [DllImport(Library, CallingConvention = CallingConvention.Cdecl)] internal static extern IntPtr sqlite3_column_text(IntPtr statement, int column);
    }

    /// <summary>Native database contract used by the isolated runtime.</summary>
    public sealed class Database : IDisposable {
        /// <summary>Native native directory contract used by the isolated runtime.</summary>
        public static string NativeDirectory = "";
        /// <summary>Native db contract used by the isolated runtime.</summary>
        IntPtr db;
        /// <summary>Opens a QuietCli database and initializes its schema when permitted.</summary>
        /// <remarks>Uses FULLMUTEX and a 2000 ms busy timeout. When creating, rejects a foreign database, then transactionally initializes QuietCli2 schema 1. Read-only mode requires QuietCli2 schema 1. Closes the handle on error.</remarks>
        /// <param name="path">Path to the SQLite file to open.</param>
        /// <param name="create">True permits reading, writing, creation and migration; false enforces read-only access.</param>
        public Database(string path, bool create) {
            try {
                if (create) Protect(path);
                Check(Sqlite.sqlite3_open_v2(path, out db, (create ? 6 : 1) | 0x10000, IntPtr.Zero));
                Check(Sqlite.sqlite3_busy_timeout(db, 2000));
                long version = (long)Query("PRAGMA user_version", Array.Empty<object>())[0]["user_version"];
                if (version > 1) throw new InvalidOperationException("Unsupported QuietCli2 schema.");
                if (create && version == 0) {
                    Execute("BEGIN IMMEDIATE", Array.Empty<object>());
                    try {
                        long lockedVersion = (long)Query("PRAGMA user_version", Array.Empty<object>())[0]["user_version"];
                        if (lockedVersion == 1) { Execute("COMMIT", Array.Empty<object>()); return; }
                        long existing = (long)Query("SELECT COUNT(*) AS n FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'", Array.Empty<object>())[0]["n"];
                        if (existing != 0) throw new InvalidOperationException("Foreign database.");
                        Execute("CREATE TABLE quiet2_events(id TEXT PRIMARY KEY,kind TEXT NOT NULL,timestamp_ms INTEGER NOT NULL,parent_id TEXT,root_id TEXT,session_id TEXT,context TEXT,role TEXT,command TEXT,outcome TEXT,payload TEXT NOT NULL)", Array.Empty<object>());
                        Execute("CREATE INDEX quiet2_time ON quiet2_events(timestamp_ms)", Array.Empty<object>());
                        Execute("CREATE INDEX quiet2_context ON quiet2_events(context,session_id)", Array.Empty<object>());
                        Execute("PRAGMA user_version=1", Array.Empty<object>());
                        Execute("COMMIT", Array.Empty<object>());
                    } catch { Execute("ROLLBACK", Array.Empty<object>()); throw; }
                } else if (!create && version != 1) throw new InvalidOperationException("Not a QuietCli2 database.");
            } catch { Dispose(); throw; }
        }
        /// <summary>Prepares the database file so that only its owner can read it.</summary>
        /// <remarks>History holds execution counter metadata only. SQLite gives its -wal and -shm companions the mode of the main file. An existing shared parent directory is left unchanged; Windows inherits the ACL of the profile.</remarks>
        /// <param name="path">Path to the SQLite file to open.</param>
        static void Protect(string path) {
            string directory = Path.GetDirectoryName(Path.GetFullPath(path));
            if (OperatingSystem.IsWindows()) { Directory.CreateDirectory(directory); return; }
            const UnixFileMode ownerOnly = UnixFileMode.UserRead | UnixFileMode.UserWrite;
            Directory.CreateDirectory(directory, ownerOnly | UnixFileMode.UserExecute);
            if (File.Exists(path)) {
                if ((File.GetUnixFileMode(path) & ~ownerOnly) != 0) File.SetUnixFileMode(path, ownerOnly);
                return;
            }
            try { using var created = new FileStream(path, new FileStreamOptions { Mode = FileMode.CreateNew, Access = FileAccess.Write, UnixCreateMode = ownerOnly }); }
            catch (IOException) when (File.Exists(path)) { }
        }
        /// <summary>Converts a SQLite error code to a .NET exception.</summary>
        /// <remarks>Accepts code zero. Other codes throw InvalidOperationException with the handle message when available.</remarks>
        /// <param name="code">SQLite result code to check.</param>
        void Check(int code) {
            if (code != 0) throw new InvalidOperationException("SQLite " + code + ": " +
                (db == IntPtr.Zero ? "cannot open database" : Marshal.PtrToStringUTF8(Sqlite.sqlite3_errmsg(db))));
        }
        /// <summary>Prepares a query and binds positional values.</summary>
        /// <remarks>Unwraps PSObject; binds null, UTF-8 text, floating-point values or integers according to type. Finalizes the statement if preparation or binding fails. The caller must finalize the returned handle.</remarks>
        /// <param name="sql">Query with positional ? parameters.</param>
        /// <param name="values">Values to bind in order, using SQLite indices starting at one.</param>
        /// <returns>Prepared statement handle.</returns>
        IntPtr Prepare(string sql, object[] values) {
            IntPtr statement = IntPtr.Zero;
            try {
                Check(Sqlite.sqlite3_prepare_v2(db, sql, -1, out statement, IntPtr.Zero));
                for (int i = 0; i < values.Length; i++) {
                    object value = values[i]; int code;
                if (value is not null && value.GetType().FullName == "System.Management.Automation.PSObject") value = value.GetType().GetProperty("BaseObject").GetValue(value);
                    if (value == null) code = Sqlite.sqlite3_bind_null(statement, i + 1);
                    else if (value is string text) {
                        byte[] bytes = Encoding.UTF8.GetBytes(text + "\0");
                        code = Sqlite.sqlite3_bind_text(statement, i + 1, bytes, bytes.Length - 1, new IntPtr(-1));
                    } else if (value is double || value is float || value is decimal)
                        code = Sqlite.sqlite3_bind_double(statement, i + 1, Convert.ToDouble(value, CultureInfo.InvariantCulture));
                    else code = Sqlite.sqlite3_bind_int64(statement, i + 1, Convert.ToInt64(value, CultureInfo.InvariantCulture));
                    Check(code);
                }
                return statement;
            } catch { if (statement != IntPtr.Zero) Sqlite.sqlite3_finalize(statement); throw; }
        }
        /// <summary>Executes a SQL statement and ignores any rows it returns.</summary>
        /// <remarks>Advances to SQLITE_DONE (101), checks other outcomes and always finalizes the statement. Queries are prepared with bound values.</remarks>
        /// <param name="sql">SQL statement to execute.</param>
        /// <param name="values">Values bound to positional parameters.</param>
        public void Execute(string sql, object[] values) {
            IntPtr statement = Prepare(sql, values);
            try { int code; do { code = Sqlite.sqlite3_step(statement); } while (code == 100); if (code != 101) Check(code); }
            finally { Sqlite.sqlite3_finalize(statement); }
        }
        /// <summary>Reads rows from a parameterized query.</summary>
        /// <remarks>Converts SQLite columns to Int64, Double, null or UTF-8 text according to type. Always finalizes the statement and propagates read errors.</remarks>
        /// <param name="sql">SQL read query.</param>
        /// <param name="values">Values bound to positional parameters.</param>
        /// <returns>List of dictionaries indexed by column name.</returns>
        public List<Dictionary<string, object>> Query(string sql, object[] values) {
            var rows = new List<Dictionary<string, object>>(); IntPtr statement = Prepare(sql, values);
            try {
                int code;
                while ((code = Sqlite.sqlite3_step(statement)) == 100) {
                    var row = new Dictionary<string, object>();
                    for (int column = 0; column < Sqlite.sqlite3_column_count(statement); column++) {
                        string name = Marshal.PtrToStringUTF8(Sqlite.sqlite3_column_name(statement, column));
                        int type = Sqlite.sqlite3_column_type(statement, column);
                        row[name] = type == 1 ? (object)Sqlite.sqlite3_column_int64(statement, column) :
                            type == 2 ? (object)Sqlite.sqlite3_column_double(statement, column) :
                            type == 5 ? null : Marshal.PtrToStringUTF8(Sqlite.sqlite3_column_text(statement, column));
                    }
                    rows.Add(row);
                }
                if (code != 101) Check(code);
            } finally { Sqlite.sqlite3_finalize(statement); }
            return rows;
        }
        /// <summary>Closes the SQLite handle still held.</summary>
        /// <remarks>Uses sqlite3_close_v2, then resets the handle to zero; subsequent calls have no effect.</remarks>
        public void Dispose() { if (db != IntPtr.Zero) { Sqlite.sqlite3_close_v2(db); db = IntPtr.Zero; } }
    }
}
