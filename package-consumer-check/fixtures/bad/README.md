# Fixture.Widgets

```bash
dotnet add package Fixture.Widgets
```

<!-- snippet: compile packages="Fixture.Widgets" -->
```csharp
using Fixture.Widgets;

var widget = new Widget("first");
widget.Name = "no setter";
```

<!-- snippet: compile packages="Fixture.Widgets Microsoft.Extensions.DependencyInjection" -->
```csharp
Console.WriteLine("needs a package nobody was told to install");
```

<!-- snippet: compile packages="Fixture.Widgets" -->
Text where a fence should be.
