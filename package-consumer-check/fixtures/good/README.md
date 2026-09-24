# Fixture.Widgets

```bash
dotnet add package Fixture.Widgets
```

<!-- snippet: compile packages="Fixture.Widgets" -->
```csharp
using Fixture.Widgets;

var widget = new Widget("first");
Console.WriteLine(widget.Name);
```

An unmarked fragment is not compiled:

```csharp
widget.Name = "no setter";
```
