--[[
    DrawingLibrary — full feature demo.
    Loads the library straight from GitHub (raw) via loadstring, the standard
    executor pattern. Run in a Drawing-capable environment.

    Repo: https://github.com/joaoswu/VexUI
]]

local URL = "https://raw.githubusercontent.com/joaoswu/VexUI/main/DrawingLibrary.luau"
local Library = loadstring(game:HttpGet(URL))()

-- ── Create a window ────────────────────────────────────────────────────────
local Window = Library:CreateWindow({
	Title = "DrawingLibrary  •  Demo",
	Size  = Vector2.new(540, 460),
	Theme = "Dark",
})

-- ── Tab 1: every input component ───────────────────────────────────────────
local Main = Window:CreateTab("Main")

local Inputs = Main:CreateSection("Inputs")

Inputs:CreateLabel({ Text = "Welcome — try every control below." })

Inputs:CreateButton({
	Name = "Click Me",
	Callback = function()
		Library:Notify({ Title = "Button", Message = "You clicked the button!", Type = "success" })
	end,
})

local toggle = Inputs:CreateToggle({
	Name = "Enable Feature",
	Default = false,
	Flag = "FeatureEnabled",
	Callback = function(v) print("[toggle]", v) end,
})

Inputs:CreateSlider({
	Name = "FOV",
	Min = 1, Max = 360, Default = 90, Step = 1, Suffix = "°",
	Callback = function(v) print("[slider] fov", v) end,
})

Inputs:CreateSlider({
	Name = "Smoothness",
	Min = 0, Max = 1, Default = 0.35, Step = 0.05,
	Callback = function(v) print("[slider] smooth", v) end,
})

local dd = Inputs:CreateDropdown({
	Name = "Mode",
	Options = { "Off", "Silent", "Assist", "Legit", "Rage" },
	Default = "Assist",
	Search = true,
	Callback = function(v) print("[dropdown]", v) end,
})

Inputs:CreateDropdown({
	Name = "Targets",
	Options = { "Head", "Torso", "Arms", "Legs", "Random" },
	Default = { "Head", "Torso" },
	Multi = true,
	Callback = function(list) print("[multi]", table.concat(list, ", ")) end,
})

Inputs:CreateTextbox({
	Name = "Username",
	Placeholder = "enter name...",
	Default = "",
	Callback = function(text) print("[textbox]", text) end,
})

Inputs:CreateKeybind({
	Name = "Toggle Menu",
	Default = Enum.KeyCode.RightShift,
	Callback = function() Window:Toggle() end,
})

Inputs:CreateColorPicker({
	Name = "ESP Color",
	Default = Color3.fromRGB(120, 110, 245),
	Callback = function(c) print("[color]", c) end,
})

-- A second column-style section to show grouping
local Visuals = Main:CreateSection("Visuals")
Visuals:CreateSearchbar({ Placeholder = "filter visuals..." })
Visuals:CreateToggle({ Name = "Box ESP",     Default = true })
Visuals:CreateToggle({ Name = "Name ESP",    Default = false })
Visuals:CreateToggle({ Name = "Tracer Lines",Default = false })
Visuals:CreateToggle({ Name = "Health Bars", Default = true })
Visuals:CreateSlider({ Name = "Box Thickness", Min = 1, Max = 5, Default = 2, Step = 1 })

-- ── Tab 2: settings / theme switching ──────────────────────────────────────
local Settings = Window:CreateTab("Settings")
local Theme = Settings:CreateSection("Theme")

Theme:CreateDropdown({
	Name = "Preset",
	Options = { "Dark", "Light" },
	Default = "Dark",
	Callback = function(name) Library:SetTheme(name) end,
})

Theme:CreateColorPicker({
	Name = "Accent",
	Default = Color3.fromRGB(120, 110, 245),
	Callback = function(c) Library:SetTheme({ Accent = c, SliderFill = c, ToggleOn = c, AccentDim = c }) end,
})

Theme:CreateButton({
	Name = "Spawn Notifications",
	Callback = function()
		Library:Notify({ Title = "Info",    Message = "An informational toast.", Type = "info" })
		task.wait(0.3)
		Library:Notify({ Title = "Success", Message = "Operation completed.",     Type = "success" })
		task.wait(0.3)
		Library:Notify({ Title = "Warning", Message = "Be careful here.",          Type = "warning" })
		task.wait(0.3)
		Library:Notify({ Title = "Error",   Message = "Something went wrong.",      Type = "error" })
	end,
})

local Misc = Settings:CreateSection("Misc")
Misc:CreateButton({
	Name = "Read Toggle State via :Get()",
	Callback = function()
		Library:Notify({ Title = "Flag", Message = "FeatureEnabled = " .. tostring(toggle:Get()) })
	end,
})
Misc:CreateButton({
	Name = "Set Dropdown to 'Rage' via :Set()",
	Callback = function() dd:Set("Rage") end,
})
Misc:CreateButton({
	Name = "Destroy UI",
	Callback = function() Library:Destroy() end,
})

print("Demo loaded. Press RightShift to toggle the window.")
