namespace FrenchExDev2.QuietCli;

/// <summary>Coordinates active measurement writes to the same full path within this process.</summary>
internal static class MeasurementWriteGate
{
    /// <summary>Protects registration and removal of owners and asynchronous waiters.</summary>
    private static readonly object sync = new();
    /// <summary>Retains entries only while an operation owns or awaits them.</summary>
    private static readonly Dictionary<string, Entry> entries = new(OperatingSystem.IsWindows() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);

    /// <summary>Waits without blocking a worker thread; different database paths remain independent.</summary>
    /// <param name="path">Database path, normalized without creating or opening a file.</param>
    /// <returns>An idempotent lease released after the complete SQLite operation.</returns>
    internal static async ValueTask<IDisposable> EnterAsync(string path)
    {
        string key = Path.GetFullPath(path);
        Entry entry;
        lock (sync)
        {
            if (!entries.TryGetValue(key, out entry!)) entries.Add(key, entry = new Entry());
            entry.Users++;
        }
        await entry.Semaphore.WaitAsync();
        return new Lease(key, entry);
    }

    /// <summary>One live database's owner and pending operations.</summary>
    private sealed class Entry
    {
        /// <summary>Serializes operations rather than relying on SQLite's busy timeout for local arbitration.</summary>
        internal readonly SemaphoreSlim Semaphore = new(1, 1);
        /// <summary>Owners plus waiters, changed only while holding sync.</summary>
        internal int Users;
    }

    /// <summary>Releases ownership and removes the last unused registration.</summary>
    /// <param name="key">Normalized registration key.</param>
    /// <param name="entry">Entry owned by this operation.</param>
    private sealed class Lease(string key, Entry entry) : IDisposable
    {
        /// <summary>Null after the first disposal, including concurrent disposal attempts.</summary>
        private Entry? owned = entry;

        /// <summary>Releases exactly once without retaining an idle database registration.</summary>
        public void Dispose()
        {
            var current = Interlocked.Exchange(ref owned, null);
            if (current is null) return;
            lock (sync)
            {
                current.Semaphore.Release();
                if (--current.Users == 0)
                {
                    entries.Remove(key);
                    current.Semaphore.Dispose();
                }
            }
        }
    }
}
