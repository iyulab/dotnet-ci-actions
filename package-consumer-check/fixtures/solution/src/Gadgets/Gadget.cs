using System.Collections.Generic;

namespace Fixture.Gadgets;

/// <summary>A thing assembled from parts.</summary>
public sealed class Gadget(params Part[] parts)
{
    /// <summary>The parts given at construction.</summary>
    public IReadOnlyList<Part> Parts { get; } = parts;
}
