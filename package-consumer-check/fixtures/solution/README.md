# Fixture.Gadgets

A solution the way a consuming repository has one: two packed libraries, one referencing the other,
and a test project that references both and is not packed.

```bash
dotnet add package Fixture.Gadgets
dotnet add package Fixture.Gadgets.Core
```

<!-- snippet: compile packages="Fixture.Gadgets Fixture.Gadgets.Core" -->
```csharp
using Fixture.Gadgets;

var gadget = new Gadget(new Part("spring"), new Part("gear"));
Console.WriteLine(gadget.Parts.Count);
```
