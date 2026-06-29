# DrawingLibrary

A complete, production-quality **Roblox `Drawing` API** UI library. It renders a
modern, utility-style menu **entirely in screen space** — no `ScreenGui`, no
`Frame`/`TextLabel`, no `Instance`-based UI of any kind. Everything is drawn with
`Drawing.new("Square" | "Text" | "Line" | "Circle")` and driven by
`UserInputService` + `RunService.RenderStepped`.

> **Environment:** requires a runtime that exposes the global `Drawing` API
> (i.e. an exploit/executor or a Drawing shim). All other code is pure Luau.

---

## Features

| Component | Highlights |
|-----------|-----------|
| **Window** | Drag, resize (corner grip), collapse, close, title bar, layered drop shadow |
| **Tabs** | Switchable tab navigation per window |
| **Section** | Bordered, labelled grouping of elements |
| **Button** | Hover / press feedback + callback |
| **Toggle** | Animated knob with eased transition |
| **Slider** | Min/Max/Step, live value label, suffix, drag or click |
| **Dropdown** | Single or multi-select, scrollable, optional live search |
| **Textbox** | Real keyboard input, caret rendering, placeholder, numeric mode |
| **Label** | Static or dynamically updatable text |
| **Keybind** | Click-to-bind, Toggle/Hold modes, global activation |
| **Color Picker** | HSV field + hue bar + hex input + swatch, live callback |
| **Notifications** | Timed toasts (info/success/warning/error) with slide animations |
| **Searchbar** | Real-time filtering of a section's elements |

Plus: two polished built-in themes (**Dark** / **Light**), full theme hot-swap,
z-index layering (popups & toasts always on top), eased tween utility, viewport
resize handling, and leak-free `Library:Destroy()`.

---

## Install

Drop `DrawingLibrary.lua` into your project (e.g. as a `ModuleScript`) and
`require` it. See `example.lua` for a full working demo.

```lua
local Library = require(path.to.DrawingLibrary)

local Window  = Library:CreateWindow({ Title = "My Menu", Size = Vector2.new(520, 420) })
local Tab     = Window:CreateTab("Combat")
local Section = Tab:CreateSection("Settings")

Section:CreateToggle({ Name = "Enable", Default = false, Callback = function(v) end })
Section:CreateSlider({ Name = "FOV", Min = 1, Max = 360, Default = 90, Step = 1,
    Callback = function(v) end })
Section:CreateKeybind({ Name = "Toggle Menu", Default = Enum.KeyCode.RightShift,
    Callback = function() Window:Toggle() end })
```

Every component handle exposes `:Set(value)`, `:Get()`, `:SetVisible(bool)` and
`:Destroy()`.

---

## API reference

The **full API reference** — every method, parameter type, theme property, and
per-component example — lives in the doc comment at the top of
[`DrawingLibrary.lua`](DrawingLibrary.lua).

### Theming

```lua
Library:SetTheme("Light")                 -- swap to a built-in preset
Library:SetTheme({ Accent = Color3.fromRGB(255, 90, 120) }) -- partial merge, hot-swaps live
local t = Library:GetTheme()              -- copy of the active theme
Library:RegisterTheme("Mint", { Accent = Color3.fromRGB(80, 220, 170) })
```

Partial theme tables **merge** into the active theme rather than replacing it, and
the change propagates to every live element immediately.

---

## Notes

* **Mouse offset:** some executors render Drawing objects in a coordinate space
  offset from `GetMouseLocation()` by the topbar inset. If clicks land ~36px off
  vertically, set `Library.MouseOffset = Vector2.new(0, 36)` (or `-36`).
* **Rounded corners** are simulated with corner circles when
  `Theme.CornerRadius > 0`. Set it to `0` for the leanest Drawing-object count
  and crisp square corners.
* The library is **retained-mode**: objects are created once and only
  repositioned on layout changes. The render loop never allocates per frame.
* Always call `Library:Destroy()` on teardown — it removes every Drawing object
  and disconnects every connection.
