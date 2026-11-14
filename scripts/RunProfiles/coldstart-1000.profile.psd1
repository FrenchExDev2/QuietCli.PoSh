# Run profile 'coldstart-1000'. Data only: parsed in restricted language mode, never executed.
@{
    SchemaVersion = 1
    Name = 'coldstart-1000'
    Description = 'Cold-start A/B, 1000 measured pairs (about 80 minutes): statistical noise elimination.'
    Script = 'Measure-ColdStart.ps1'
    Parameters = @{
        BootstrapResamples = 5000
        Confidence = 0.99
        MaxFailedPairs = 20
        Runs = 1000
        Seed = 20261107
        Warmup = 10
    }
}
