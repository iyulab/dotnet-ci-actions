namespace Fixture.Widgets;

/// <summary>A thing with a name.</summary>
public sealed class Widget(string name)
{
    /// <summary>The name given at construction.</summary>
    public string Name { get; } = name;
}
