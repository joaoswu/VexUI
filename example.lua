--[[
    VexUI — Abyss-style demo.
    Loads the library straight from GitHub (raw) via loadstring.
    Run in a Drawing-capable executor.

    Repo: https://github.com/joaoswu/VexUI
]]

local URL = "https://raw.githubusercontent.com/joaoswu/VexUI/main/DrawingLibrary.lua?v=10"
local Library = loadstring(game:HttpGet(URL))()

local Window = Library:CreateWindow({
    Title = "Abyss V3",
    Size  = Vector2.new(560, 480),
    Theme = "Dark",
})

-- ── MAIN TAB ───────────────────────────────────────────────────────────────
local Main = Window:CreateTab("Main")

-- left column (side "Left" is the default)
local Aim = Main:CreateSection("Aim Assist", "Left")
Aim:CreateToggle({ Name = "Enabled", Default = false, Flag = "AimEnabled" })
Aim:CreateSlider({ Name = "Aimbot FOV", Min = 0, Max = 250, Default = 100, Suffix = "°" })
Aim:CreateSlider({ Name = "Smoothing", Min = 0, Max = 10, Default = 5 })
Aim:CreateDropdown({ Name = "Smoothing Type", Options = { "Linear", "Eased", "Exponential" }, Default = "Linear" })
Aim:CreateSlider({ Name = "Randomization", Min = 0, Max = 20, Default = 5 })
Aim:CreateDropdown({ Name = "Hitscan Priority", Options = { "Head", "Torso", "Nearest" }, Default = "Head" })
Aim:CreateKeybind({ Name = "Aimbot Key", Default = Enum.KeyCode.E })
Aim:CreateToggle({ Name = "Target Prediction", Default = false })

local Recoil = Main:CreateSection("Recoil Control", "Left")
Recoil:CreateToggle({ Name = "Weapon RCS", Default = false })
Recoil:CreateSlider({ Name = "Recoil Control X", Min = 0, Max = 100, Default = 10, Suffix = "%" })
Recoil:CreateSlider({ Name = "Recoil Control Y", Min = 0, Max = 100, Default = 10, Suffix = "%" })

-- right column
local Trigger = Main:CreateSection("Trigger Bot", "Right")
Trigger:CreateToggle({ Name = "Enabled", Default = false })
Trigger:CreateDropdown({ Name = "Hitboxes", Options = { "Head", "Torso", "Any" }, Default = "Head" })
Trigger:CreateToggle({ Name = "Trigger When Aiming", Default = false })
Trigger:CreateSlider({ Name = "Aim Percentage", Min = 1, Max = 100, Default = 1, Suffix = "%" })

local Bullet = Main:CreateSection("Bullet Redirection", "Right")
Bullet:CreateToggle({ Name = "Silent Aim", Default = false })
Bullet:CreateSlider({ Name = "Silent Aim FOV", Min = 0, Max = 250, Default = 100, Suffix = "°" })
Bullet:CreateSlider({ Name = "Hit Chance", Min = 0, Max = 100, Default = 30, Suffix = "%" })
Bullet:CreateSlider({ Name = "Accuracy", Min = 0, Max = 100, Default = 90, Suffix = "%" })
Bullet:CreateColorPicker({ Name = "Tracer Color", Default = Color3.fromRGB(88, 128, 168) })

-- ── VISUALS TAB ──────────────────────────────────────────────────────────────
local Visuals = Window:CreateTab("Visuals")
local Esp = Visuals:CreateSection("ESP", "Left")
Esp:CreateSearchbar({ Placeholder = "search..." })
Esp:CreateToggle({ Name = "Box ESP", Default = true })
Esp:CreateToggle({ Name = "Name ESP", Default = false })
Esp:CreateToggle({ Name = "Health Bars", Default = true })
Esp:CreateSlider({ Name = "Box Thickness", Min = 1, Max = 5, Default = 2 })

local World = Visuals:CreateSection("World", "Right")
World:CreateToggle({ Name = "Fullbright", Default = false })
World:CreateColorPicker({ Name = "Ambient", Default = Color3.fromRGB(120, 150, 190) })

-- ── SETTINGS TAB ─────────────────────────────────────────────────────────────
local Settings = Window:CreateTab("Settings")
local Theme = Settings:CreateSection("Theme", "Left")
Theme:CreateDropdown({ Name = "Preset", Options = { "Dark", "Light" }, Default = "Dark",
    Callback = function(name) Library:SetTheme(name) end })
Theme:CreateColorPicker({ Name = "Accent", Default = Color3.fromRGB(88, 128, 168),
    Callback = function(c) Library:SetTheme({ Accent = c, SliderFill = c, ToggleOn = c }) end })
Theme:CreateButton({ Name = "Test Notification",
    Callback = function() Library:Notify({ Title = "VexUI", Message = "It works!", Type = "success" }) end })

local Menu = Settings:CreateSection("Menu", "Right")
Menu:CreateKeybind({ Name = "Toggle UI", Default = Enum.KeyCode.RightShift,
    Callback = function() Window:Toggle() end })
Menu:CreateButton({ Name = "Unload", Callback = function() Library:Destroy() end })

print("VexUI loaded — press RightShift to toggle.")
