// A test about drive paths has to be handed one, and a guard has to spell what it forbids.
namespace Sample;

public static class PathTests
{
    public const string Input = "D:/data/lib";
    public const string Forbidden = "cycle-42";
}
