using System.Management.Automation;
using System.Runtime.CompilerServices;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Provides caller-local classification and actions on completed PowerShell results.</summary>
public static class ResultMethods
{
    private static readonly ConditionalWeakTable<PSObject, Rules> LocalRules = new();
    private static readonly PSCodeMethod[] Methods =
    [
        Method(nameof(AsSuccessWhen), nameof(AsSuccessWhen)),
        Method(nameof(AsFailureWhen), nameof(AsFailureWhen)),
        Method(nameof(OnSuccess), nameof(OnSuccess)),
        Method(nameof(OnFailure), nameof(OnFailure)),
        Method("Success", nameof(OnSuccess)),
        Method("Succes", nameof(OnSuccess)),
        Method("Failure", nameof(OnFailure)),
    ];

    /// <summary>Initializes the common envelope type and its fluent PowerShell methods.</summary>
    /// <param name="result">A new live or replay result.</param>
    internal static void Attach(PSObject result)
    {
        result.TypeNames.Insert(0, "QuietCli2.Result");
        foreach (PSCodeMethod method in Methods) result.Methods.Add(method);
    }

    /// <summary>Sets a predicate that must match for a result to be classified as successful.</summary>
    /// <param name="result">The receiving result, also returned for chaining.</param>
    /// <param name="predicate">Receives the result and returns one Boolean.</param>
    public static PSObject AsSuccessWhen(PSObject result, ScriptBlock predicate) => SetRule(result, predicate, success: true);

    /// <summary>Sets a predicate that classifies a result as failed when it matches.</summary>
    /// <param name="result">The receiving result, also returned for chaining.</param>
    /// <param name="predicate">Receives the result and returns one Boolean.</param>
    public static PSObject AsFailureWhen(PSObject result, ScriptBlock predicate) => SetRule(result, predicate, success: false);

    /// <summary>Runs an action if the result is classified as successful.</summary>
    /// <param name="result">The receiving result, also returned for chaining.</param>
    /// <param name="action">Receives the result. Its success-stream output is discarded.</param>
    public static PSObject OnSuccess(PSObject result, ScriptBlock action) => RunBranch(result, action, success: true);

    /// <summary>Runs an action if the result is classified as failed.</summary>
    /// <param name="result">The receiving result, also returned for chaining.</param>
    /// <param name="action">Receives the result. Its success-stream output is discarded.</param>
    public static PSObject OnFailure(PSObject result, ScriptBlock action) => RunBranch(result, action, success: false);

    private static PSCodeMethod Method(string name, string implementation) =>
        new(name, typeof(ResultMethods).GetMethod(implementation)!);

    private static PSObject SetRule(PSObject result, ScriptBlock predicate, bool success)
    {
        ArgumentNullException.ThrowIfNull(predicate);
        Rules rules = LocalRules.GetOrCreateValue(result);
        rules.CheckNotEvaluating();
        if (success) rules.Success = predicate;
        else rules.Failure = predicate;
        rules.Decision = null;
        return result;
    }

    private static PSObject RunBranch(PSObject result, ScriptBlock action, bool success)
    {
        ArgumentNullException.ThrowIfNull(action);
        Rules rules = LocalRules.GetOrCreateValue(result);
        rules.CheckNotEvaluating();
        rules.Decision ??= Classify(result, rules);
        if (rules.Decision == success) action.InvokeReturnAsIs(result);
        return result;
    }

    private static bool Classify(PSObject result, Rules rules)
    {
        rules.Evaluating = true;
        try
        {
            if (rules.Failure is { } failure && Evaluate(result, failure, nameof(AsFailureWhen))) return false;
            if (rules.Success is { } success) return Evaluate(result, success, nameof(AsSuccessWhen));
            if (rules.Failure is not null) return true;

            object? completeness = FinalProperties.GetCompleteness(result);
            return string.Equals(QuietRuntime.Unwrap(Members.Get(result, "Outcome")) as string, "Success", StringComparison.OrdinalIgnoreCase)
                && LanguagePrimitives.IsTrue(Members.Get(completeness, "Source"))
                && LanguagePrimitives.IsTrue(Members.Get(completeness, "Analysis"))
                && QuietRuntime.Unwrap(Members.Get(result, "Error")) is Array { Length: 0 };
        }
        finally { rules.Evaluating = false; }
    }

    private static bool Evaluate(PSObject result, ScriptBlock predicate, string name)
    {
        var output = predicate.Invoke(result);
        if (output.Count == 1 && QuietRuntime.Unwrap(output[0]) is bool decision) return decision;
        throw new InvalidOperationException($"QuietResultPredicateMustReturnBoolean: {name}");
    }

    private sealed class Rules
    {
        internal ScriptBlock? Success { get; set; }
        internal ScriptBlock? Failure { get; set; }
        internal bool? Decision { get; set; }
        internal bool Evaluating { get; set; }

        internal void CheckNotEvaluating()
        {
            if (Evaluating) throw new InvalidOperationException("QuietResultPredicateReentry");
        }
    }
}
