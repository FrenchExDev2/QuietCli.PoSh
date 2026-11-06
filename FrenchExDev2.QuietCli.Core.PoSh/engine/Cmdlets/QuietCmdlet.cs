using System.Management.Automation;

namespace FrenchExDev2.QuietCli.Cmdlets;

/// <summary>Shared behavior for the module's compiled cmdlets: stable error codes and the caller's working directory.</summary>
public abstract class QuietCmdlet : PSCmdlet
{
    /// <summary>Filesystem directory of the caller's current location, used for relative paths.</summary>
    protected string CurrentDirectory => SessionState.Path.CurrentFileSystemLocation.ProviderPath;

    /// <summary>Raises a terminating error whose exception message is the stable code.</summary>
    /// <param name="code">Stable error code or code-and-detail text.</param>
    protected void Fail(string code) =>
        ThrowTerminatingError(new ErrorRecord(new InvalidOperationException(code), code.Split(':')[0], ErrorCategory.InvalidOperation, null));

    /// <summary>Resolves one effective setting using the shared precedence rules.</summary>
    /// <param name="name">Closed section.key setting name.</param>
    protected object? Setting(string name) => ConfigurationService.Snapshot(CurrentDirectory).Values[name];

    /// <summary>
    /// Finds a function through the function drive only. Unlike command discovery it never scans the module path,
    /// which costs seconds when PSModulePath contains a large source tree.
    /// </summary>
    /// <param name="name">Function name without the drive prefix.</param>
    protected FunctionInfo? FindFunction(string name)
    {
        string path = "function:" + name;
        if (!SessionState.InvokeProvider.Item.Exists(path)) return null;
        return SessionState.InvokeProvider.Item.Get(path).FirstOrDefault()?.BaseObject as FunctionInfo;
    }

    /// <summary>Raises a terminating error that carries the original exception, so callers can inspect its Data.</summary>
    /// <param name="error">Failure to surface unchanged.</param>
    protected void FailWith(Exception error) =>
        ThrowTerminatingError(new ErrorRecord(error, error.Message.Split(':')[0], ErrorCategory.InvalidOperation, null));

    /// <summary>Raises a terminating error for an exception, keeping the innermost message as the stable code.</summary>
    /// <param name="error">Failure thrown by a shared service.</param>
    protected void Fail(Exception error) => Fail(ConfigurationService.Innermost(error).Message);
}
