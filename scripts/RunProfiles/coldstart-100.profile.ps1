# Run profile 'coldstart-100'. Data only: parsed in restricted language mode, never executed.
@{
    SchemaVersion = 1
    Name = 'coldstart-100'
    Description = 'Cold-start A/B, 100 measured pairs (about 8 minutes): detects differences of a few percent.'
    Script = 'Measure-ColdStart.ps1'
    Parameters = @{
        BootstrapResamples = 2000
        Confidence = 0.95
        MaxFailedPairs = 5
        Runs = 100
        Seed = 20261107
        Warmup = 5
    }
}
