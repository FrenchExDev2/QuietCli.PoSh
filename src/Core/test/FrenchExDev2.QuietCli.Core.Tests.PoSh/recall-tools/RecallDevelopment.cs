using System.Diagnostics;
using System.Text.Json;
using FrenchExDev2.QuietCli;

namespace FrenchExDev2.QuietCli;

/// <summary>Bounded reducer outcome without an exhaustive minimality claim.</summary>
public sealed record RecallReduction(RecallCapture Capture, int Attempts, bool BudgetExhausted, bool ProvenMinimal);

/// <summary>Pure companion-only generators and reproducer reduction.</summary>
public static class RecallDevelopment
{
    /// <summary>Compares explicit JSON projections structurally, ignoring object key order.</summary>
    /// <param name="first">First deliberately serialized comparison projection.</param>
    /// <param name="second">Second deliberately serialized comparison projection.</param>
    public static bool EquivalentJson(string first, string second)
    {
        using var a = JsonDocument.Parse(first);
        using var b = JsonDocument.Parse(second);
        return JsonElement.DeepEquals(a.RootElement, b.RootElement);
    }
    /// <summary>Generates reproducible nonempty fragments without changing byte order.</summary>
    /// <param name="bytes">Original single-stream bytes.</param>
    /// <param name="seed">Retained deterministic seed.</param>
    /// <param name="maximumBlock">Positive fragment bound.</param>
    public static IEnumerable<byte[]> Fragment(byte[] bytes, int seed, int maximumBlock)
    {
        if (maximumBlock < 1) throw new ArgumentOutOfRangeException(nameof(maximumBlock));
        var random = new Random(seed);
        for (int at = 0; at < bytes.Length;)
        {
            int size = (int)Math.Min(bytes.Length - at, random.NextInt64(1, (long)maximumBlock + 1));
            yield return bytes.AsSpan(at, size).ToArray(); at += size;
        }
    }

    /// <summary>Greedily removes events while preserving an explicit failure predicate.</summary>
    /// <param name="capture">Original reproducer.</param>
    /// <param name="fails">Independent, bounded, synchronous failure predicate.</param>
    /// <param name="maximumAttempts">Positive predicate execution budget.</param>
    /// <param name="seconds">Positive elapsed budget, checked between predicate calls.</param>
    public static Task<RecallReduction> ReduceAsync(RecallCapture capture, Func<RecallCapture, bool> fails, int maximumAttempts, double seconds)
    {
        if (maximumAttempts < 1 || !double.IsFinite(seconds) || seconds <= 0) throw new ArgumentOutOfRangeException(nameof(maximumAttempts));
        var watch = Stopwatch.StartNew(); int attempts = 1;
        if (!fails(capture)) throw new ArgumentException("RecallPredicateDoesNotFail");
        var best = capture; int index = 0;
        while (index < best.Events.Count && attempts < maximumAttempts && watch.Elapsed.TotalSeconds < seconds)
        {
            var candidate = new RecallCapture(Guid.NewGuid().ToString("N"), best.Events.Where((_, i) => i != index), capture.ReceivedBytes, capture.SourceComplete, capture.Settings, capture.CaptureId, "Event reduction", capture.SourceStatus);
            attempts++;
            if (fails(candidate)) best = candidate; else index++;
        }
        return Task.FromResult(new RecallReduction(best, attempts, index < best.Events.Count, false));
    }
}
