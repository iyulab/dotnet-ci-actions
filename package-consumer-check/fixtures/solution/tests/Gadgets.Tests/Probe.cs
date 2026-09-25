namespace Fixture.Gadgets.Tests;

internal static class Probe
{
    internal static int Count() => new Gadget(new Part("a"), new Part("b")).Parts.Count;
}
