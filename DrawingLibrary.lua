--!strict
--[[
================================================================================
  DRAWING UI LIBRARY
  A fully self-contained, Drawing-API-based utility UI library for Roblox.
  Renders entirely in screen space using the `Drawing` API. No ScreenGui,
  no Instance-based UI (Frame / TextLabel / etc.).

  Author: (your name)
  Version: 1.0.0
  Requires: An environment that exposes the global `Drawing` API
            (executor / Drawing shim). All other code is pure Luau.

================================================================================
  QUICK START
================================================================================

    local Library = require(path.to.DrawingLibrary)

    local Window = Library:CreateWindow({
        Title = "My Menu",
        Size  = Vector2.new(520, 420),
        Theme = "Dark",            -- "Dark" | "Light" | <theme table>
    })

    local Tab     = Window:CreateTab("Combat")
    local Section = Tab:CreateSection("Settings")

    Section:CreateToggle({ Name = "Enable Feature", Default = false,
        Callback = function(v) print("toggle", v) end })

    Section:CreateSlider({ Name = "FOV", Min = 1, Max = 360, Default = 90,
        Step = 1, Callback = function(v) print("fov", v) end })

    Section:CreateKeybind({ Name = "Toggle Menu", Default = Enum.KeyCode.RightShift,
        Callback = function(key) Window:Toggle() end })

================================================================================
  FULL API REFERENCE
================================================================================

  Library                                       (returned by require)
  -------
    :CreateWindow(opts) -> Window
        opts.Title  : string
        opts.Size   : Vector2          (default 520x420)
        opts.Position : Vector2?       (default centered)
        opts.Theme  : string|table?    ("Dark")
    :SetTheme(themeTable|name)          merges partial theme & hot-swaps visuals
    :GetTheme() -> table                copy of the active theme
    :Notify(opts) -> Notification       toast notification
        opts.Title   : string
        opts.Message : string
        opts.Type    : "info"|"success"|"warning"|"error"  (default "info")
        opts.Duration: number          seconds (default 4)
    :Destroy()                          removes EVERYTHING (drawings + conns)

  Window
  ------
    :CreateTab(name) -> Tab
    :SelectTab(nameOrTab)
    :Toggle()                           show/hide the whole window
    :SetVisible(bool)
    :SetTitle(text)
    :Destroy()

  Tab
  ---
    :CreateSection(name) -> Section
    :Destroy()

  Section
  -------
    :CreateButton(opts)     -> Button
    :CreateToggle(opts)     -> Toggle
    :CreateSlider(opts)     -> Slider
    :CreateDropdown(opts)   -> Dropdown
    :CreateTextbox(opts)    -> Textbox
    :CreateLabel(opts)      -> Label
    :CreateKeybind(opts)    -> Keybind
    :CreateColorPicker(opts)-> ColorPicker
    :CreateSearchbar(opts)  -> Searchbar     (filters this section's elements)
    :Destroy()

  Every component handle implements:
    :Set(value)            programmatically set its value (fires callback)
    :Get() -> value        current value
    :SetVisible(bool)      show/hide without destroying
    :Destroy()             remove just this element

  Component option tables (common fields):
    Name      : string                 label shown to the user
    Default   : <type>                  initial value
    Callback  : (value) -> ()           invoked on change
    Flag      : string?                 optional id (stored on Window.Flags)

    Button   : { Name, Callback }
    Toggle   : { Name, Default(bool), Callback }
    Slider   : { Name, Min, Max, Default, Step, Suffix?, Callback }
    Dropdown : { Name, Options(table), Default, Multi?(bool), Search?(bool), Callback }
    Textbox  : { Name, Default(string), Placeholder?, Numeric?(bool), Callback }
    Label    : { Text }
    Keybind  : { Name, Default(Enum.KeyCode), Callback, Mode?("Toggle"|"Hold") }
    ColorPicker:{ Name, Default(Color3), Alpha?(bool), Callback }
    Searchbar: { Placeholder? }

================================================================================
  THEME PROPERTIES  (all configurable; partial tables merge)
================================================================================
    Background            Color3   main window / section fill
    Foreground            Color3   raised element fill (buttons, fields)
    Accent                Color3   primary highlight / active state
    AccentDim             Color3   muted accent (focus rings, fills)
    Text                  Color3   primary text
    SubText               Color3   secondary / placeholder text
    Border                Color3   element & window borders
    Hover                 Color3   hover overlay fill
    Active                Color3   pressed / selected fill
    ToggleOn              Color3   toggle knob track when on
    ToggleOff             Color3   toggle knob track when off
    SliderFill            Color3   slider filled portion
    DropdownBackground    Color3   dropdown popup fill
    NotificationBackground Color3  toast fill
    WindowShadow          Color3   drop-shadow color
    Success               Color3   success notification accent
    Warning               Color3   warning notification accent
    Error                 Color3   error notification accent
    Info                  Color3   info notification accent
    CornerRadius          number   rounded-corner radius (0 = sharp)
    Padding               number   base spacing unit (px)
    FontSize              number   base text size (px)
    Font                  number   Drawing font id (0..3)
    Transparency          number   global fill transparency 0..1 (0 = opaque)
    StrokeWeight          number   border thickness (px)

================================================================================
  PERFORMANCE NOTES / BEST PRACTICES
================================================================================
   * The library is *retained mode*: Drawing objects are created once and
     repositioned only when layout changes (window move/resize, tab switch,
     theme change). The per-frame RenderStepped loop only advances tweens,
     blinks text cursors, and ages notifications -- it never allocates.
   * Dropdowns, color pickers and notifications render as overlays at a high
     ZIndex so they always sit above everything; they are created lazily.
   * The Drawing.Square primitive cannot be both filled and outlined, so every
     panel uses two squares (fill + border). Rounded corners are simulated with
     corner circles only when Theme.CornerRadius > 0 (set it to 0 for the
     leanest object count).
   * Keep one Library instance per session and call Library:Destroy() on
     teardown -- it removes every Drawing object and disconnects every
     connection, leaving no residual state.
================================================================================
]]

-- ============================================================================
--  SERVICES
-- ============================================================================
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")

assert(typeof(Drawing) == "table" or typeof(Drawing) == "Instance" or Drawing ~= nil,
	"DrawingLibrary: the global `Drawing` API is not available in this environment.")

-- ============================================================================
--  Z-INDEX LAYERS  (higher = drawn on top)
-- ============================================================================
local Z = {
	Shadow       = 100,
	WindowBG     = 110,
	WindowChrome = 120,
	Content      = 130,
	Element      = 140,
	ElementText  = 150,
	Popup        = 1000,
	PopupContent = 1010,
	Drag         = 8000,
	Notify       = 9000,
	NotifyText   = 9010,
}

-- ============================================================================
--  BUILT-IN THEMES
-- ============================================================================
local THEMES = {}

THEMES.Dark = {
	Background             = Color3.fromRGB(24, 25, 31),
	Foreground             = Color3.fromRGB(34, 36, 44),
	Accent                 = Color3.fromRGB(120, 110, 245),
	AccentDim              = Color3.fromRGB(70, 64, 150),
	Text                   = Color3.fromRGB(236, 237, 242),
	SubText                = Color3.fromRGB(140, 144, 158),
	Border                 = Color3.fromRGB(48, 50, 60),
	Hover                  = Color3.fromRGB(44, 46, 56),
	Active                 = Color3.fromRGB(54, 57, 70),
	ToggleOn               = Color3.fromRGB(120, 110, 245),
	ToggleOff              = Color3.fromRGB(60, 62, 74),
	SliderFill             = Color3.fromRGB(120, 110, 245),
	DropdownBackground     = Color3.fromRGB(30, 31, 39),
	NotificationBackground = Color3.fromRGB(30, 31, 39),
	WindowShadow           = Color3.fromRGB(0, 0, 0),
	Success                = Color3.fromRGB(80, 200, 120),
	Warning                = Color3.fromRGB(235, 185, 70),
	Error                  = Color3.fromRGB(235, 85, 85),
	Info                   = Color3.fromRGB(90, 150, 245),
	CornerRadius           = 6,
	Padding                = 8,
	FontSize               = 14,
	Font                   = 2,
	Transparency           = 0,
	StrokeWeight           = 1,
}

THEMES.Light = {
	Background             = Color3.fromRGB(244, 245, 248),
	Foreground             = Color3.fromRGB(255, 255, 255),
	Accent                 = Color3.fromRGB(88, 80, 236),
	AccentDim              = Color3.fromRGB(190, 186, 246),
	Text                   = Color3.fromRGB(28, 30, 38),
	SubText                = Color3.fromRGB(120, 124, 138),
	Border                 = Color3.fromRGB(216, 219, 226),
	Hover                  = Color3.fromRGB(236, 237, 242),
	Active                 = Color3.fromRGB(224, 226, 234),
	ToggleOn               = Color3.fromRGB(88, 80, 236),
	ToggleOff              = Color3.fromRGB(204, 207, 216),
	SliderFill             = Color3.fromRGB(88, 80, 236),
	DropdownBackground     = Color3.fromRGB(255, 255, 255),
	NotificationBackground = Color3.fromRGB(255, 255, 255),
	WindowShadow           = Color3.fromRGB(140, 145, 160),
	Success                = Color3.fromRGB(46, 170, 96),
	Warning                = Color3.fromRGB(214, 158, 40),
	Error                  = Color3.fromRGB(214, 64, 64),
	Info                   = Color3.fromRGB(56, 122, 224),
	CornerRadius           = 6,
	Padding                = 8,
	FontSize               = 14,
	Font                   = 2,
	Transparency           = 0,
	StrokeWeight           = 1,
}

-- ============================================================================
--  SHARED UTILITIES  (defined once, used everywhere)
-- ============================================================================
local Util = {}

function Util.clamp(v: number, a: number, b: number): number
	if v < a then return a elseif v > b then return b end
	return v
end

function Util.lerp(a: number, b: number, t: number): number
	return a + (b - a) * t
end

function Util.round(v: number): number
	return math.floor(v + 0.5)
end

-- Snap a raw value to the nearest step within [min,max].
function Util.snap(value: number, min: number, max: number, step: number): number
	if step <= 0 then return Util.clamp(value, min, max) end
	local snapped = min + Util.round((value - min) / step) * step
	-- avoid floating point fuzz on the label
	snapped = Util.round(snapped * 1e6) / 1e6
	return Util.clamp(snapped, min, max)
end

function Util.pointInRect(px: number, py: number, x: number, y: number, w: number, h: number): boolean
	return px >= x and px <= x + w and py >= y and py <= y + h
end

-- Deep-merge `src` into a fresh copy of `dst` (src wins). Used for theme merge.
function Util.merge(dst: {[any]: any}, src: {[any]: any}?): {[any]: any}
	local out = {}
	for k, v in pairs(dst) do out[k] = v end
	if src then
		for k, v in pairs(src) do out[k] = v end
	end
	return out
end

function Util.colorToHex(c: Color3): string
	return string.format("%02X%02X%02X",
		Util.round(c.R * 255), Util.round(c.G * 255), Util.round(c.B * 255))
end

function Util.hexToColor(hex: string): Color3?
	hex = (hex:gsub("#", "")):gsub("%s", "")
	if #hex == 3 then
		hex = hex:sub(1,1):rep(2) .. hex:sub(2,2):rep(2) .. hex:sub(3,3):rep(2)
	end
	if #hex ~= 6 then return nil end
	local r = tonumber(hex:sub(1, 2), 16)
	local g = tonumber(hex:sub(3, 4), 16)
	local b = tonumber(hex:sub(5, 6), 16)
	if not (r and g and b) then return nil end
	return Color3.fromRGB(r, g, b)
end

-- ---------------------------------------------------------------------------
--  EASING  (single shared library; alpha in 0..1 -> eased 0..1)
-- ---------------------------------------------------------------------------
local Ease = {}
function Ease.Linear(t: number): number return t end
function Ease.InQuad(t: number): number return t * t end
function Ease.OutQuad(t: number): number return 1 - (1 - t) * (1 - t) end
function Ease.InOutQuad(t: number): number
	return (t < 0.5) and (2 * t * t) or (1 - (-2 * t + 2) ^ 2 / 2)
end
function Ease.OutCubic(t: number): number return 1 - (1 - t) ^ 3 end
function Ease.OutBack(t: number): number
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end
local DEFAULT_EASE = Ease.OutCubic

-- ---------------------------------------------------------------------------
--  KEYCODE -> CHARACTER MAP  (for the Drawing-based textbox)
-- ---------------------------------------------------------------------------
local KEY_CHARS = {} -- [Enum.KeyCode] = { lower, shifted }
do
	-- Resolve KeyCodes by NAME and pcall-guard every lookup, so a member that
	-- doesn't exist on a given Roblox/executor version is skipped silently
	-- instead of aborting the whole module (older builds lack "Backquote").
	local function add(name: string, lo: string, hi: string)
		local ok, kc = pcall(function() return (Enum.KeyCode :: any)[name] end)
		if ok and kc ~= nil then KEY_CHARS[kc] = { lo, hi } end
	end
	for i = 0, 25 do
		local ch = string.char(97 + i)               -- a..z
		add(string.char(65 + i), ch, ch:upper())     -- KeyCode name "A".."Z"
	end
	add("Zero", "0", ")"); add("One", "1", "!"); add("Two", "2", "@")
	add("Three", "3", "#"); add("Four", "4", "$"); add("Five", "5", "%")
	add("Six", "6", "^"); add("Seven", "7", "&"); add("Eight", "8", "*")
	add("Nine", "9", "(")
	add("Space", " ", " ")
	add("Minus", "-", "_"); add("Equals", "=", "+")
	add("LeftBracket", "[", "{"); add("RightBracket", "]", "}")
	add("BackSlash", "\\", "|"); add("Backslash", "\\", "|")
	add("Semicolon", ";", ":"); add("Quote", "'", "\"")
	add("Comma", ",", "<"); add("Period", ".", ">"); add("Slash", "/", "?")
	add("Backquote", "`", "~"); add("BackQuote", "`", "~")
end

-- ============================================================================
--  LIBRARY OBJECT
-- ============================================================================
local Library = {}
Library.__index = Library

-- Internal state ------------------------------------------------------------
local state = {
	theme        = Util.merge(THEMES.Dark),
	drawings     = {} :: {[any]: boolean},   -- every live Drawing object
	connections  = {} :: {RBXScriptConnection},
	tweens       = {} :: {any},              -- active tween records
	interactives = {} :: {any},              -- registered hit-test targets
	themed       = {} :: {any},              -- objects with :ApplyTheme()
	windows      = {} :: {any},
	notifications= {} :: {any},
	captured     = nil :: any,               -- currently dragged interactive
	hovered      = nil :: any,
	focused      = nil :: any,               -- keyboard focus (textbox)
	openPopup    = nil :: any,               -- dropdown/colorpicker overlay
	destroyed    = false,
	renderConn   = nil :: RBXScriptConnection?,
}

-- ---------------------------------------------------------------------------
--  Drawing factory (every object is tracked for cleanup)
-- ---------------------------------------------------------------------------
local function mk(class: string, props: {[string]: any}?): any
	local d = Drawing.new(class)
	d.Visible = false
	if props then
		for k, v in pairs(props) do d[k] = v end
	end
	state.drawings[d] = true
	return d
end

local function destroyDrawing(d: any)
	if d and state.drawings[d] then
		state.drawings[d] = nil
		pcall(function() d:Remove() end)
	end
end

-- ---------------------------------------------------------------------------
--  Tween system (RenderStepped-driven, allocation-free per frame)
-- ---------------------------------------------------------------------------
local function lerpValue(a: any, b: any, t: number): any
	local ty = typeof(a)
	if ty == "number" then return a + (b - a) * t
	elseif ty == "Color3" then return a:Lerp(b, t)
	elseif ty == "Vector2" then return a:Lerp(b, t)
	end
	return (t < 1) and a or b
end

-- Cancel any tween targeting (owner, key) so they don't fight.
local function cancelTween(owner: any, key: string)
	for i = #state.tweens, 1, -1 do
		local tw = state.tweens[i]
		if tw.owner == owner and tw.key == key then
			table.remove(state.tweens, i)
		end
	end
end

local function tween(owner: any, key: string, from: any, to: any,
	duration: number, ease: ((number) -> number)?, onUpdate: (any) -> (), onDone: (() -> ())?)
	cancelTween(owner, key)
	if duration <= 0 then
		onUpdate(to)
		if onDone then onDone() end
		return
	end
	table.insert(state.tweens, {
		owner = owner, key = key, from = from, to = to,
		t = 0, duration = duration, ease = ease or DEFAULT_EASE,
		onUpdate = onUpdate, onDone = onDone,
	})
end

local function stepTweens(dt: number)
	for i = #state.tweens, 1, -1 do
		local tw = state.tweens[i]
		tw.t += dt
		local alpha = Util.clamp(tw.t / tw.duration, 0, 1)
		local eased = tw.ease(alpha)
		tw.onUpdate(lerpValue(tw.from, tw.to, eased))
		if alpha >= 1 then
			table.remove(state.tweens, i)
			if tw.onDone then tw.onDone() end
		end
	end
end

-- ---------------------------------------------------------------------------
--  Interactive registry  (central hit-testing)
-- ---------------------------------------------------------------------------
local function addInteractive(obj: any)
	obj._enabled = (obj._enabled ~= false)
	table.insert(state.interactives, obj)
end

local function removeInteractive(obj: any)
	for i = #state.interactives, 1, -1 do
		if state.interactives[i] == obj then
			table.remove(state.interactives, i)
			break
		end
	end
	if state.hovered == obj then state.hovered = nil end
	if state.captured == obj then state.captured = nil end
end

-- Topmost interactive under (x,y). Higher zindex wins; ties -> later registered.
local function pick(x: number, y: number): any
	local best, bestZ = nil, -math.huge
	for _, o in ipairs(state.interactives) do
		if o._enabled and o.visible ~= false and o.rect then
			local r = o.rect
			if Util.pointInRect(x, y, r.x, r.y, r.w, r.h) then
				local z = o.zindex or 0
				if z >= bestZ then best, bestZ = o, z end
			end
		end
	end
	return best
end

-- ---------------------------------------------------------------------------
--  THEME accessor helpers
-- ---------------------------------------------------------------------------
local function T(): {[string]: any}
	return state.theme
end

local function registerThemed(obj: any)
	table.insert(state.themed, obj)
end

local function unregisterThemed(obj: any)
	for i = #state.themed, 1, -1 do
		if state.themed[i] == obj then
			table.remove(state.themed, i)
			break
		end
	end
end

-- ============================================================================
--  PRIMITIVE: Panel (filled square + border, optional rounded corners)
-- ============================================================================
local Panel = {}
Panel.__index = Panel

function Panel.new(zBase: number): any
	local self = setmetatable({}, Panel)
	self.fill   = mk("Square", { Filled = true, Thickness = 0, ZIndex = zBase })
	self.border = mk("Square", { Filled = false, Thickness = T().StrokeWeight, ZIndex = zBase + 1 })
	self.corners = {} -- circle objects when rounded
	self.zBase = zBase
	self.x, self.y, self.w, self.h = 0, 0, 0, 0
	self._visible = false
	self._radius = 0
	self._hasBorder = true
	return self
end

function Panel:SetRadius(r: number)
	self._radius = r
	-- (re)create corner circles
	for _, c in ipairs(self.corners) do destroyDrawing(c) end
	self.corners = {}
	if r and r > 0 then
		for i = 1, 4 do
			self.corners[i] = mk("Circle", {
				Filled = true, Thickness = 0, NumSides = 16,
				Radius = r, ZIndex = self.zBase,
			})
		end
	end
	self:_apply()
end

function Panel:SetColors(fillColor: Color3, borderColor: Color3?, fillTransparency: number?)
	-- NOTE: in the Drawing API, Transparency is ALPHA: 1 = opaque, 0 = invisible
	-- (the opposite of Roblox Instance.Transparency). Callers pass opacity directly.
	self.fill.Color = fillColor
	self.fill.Transparency = fillTransparency or 1
	for _, c in ipairs(self.corners) do
		c.Color = fillColor
		c.Transparency = self.fill.Transparency
	end
	if borderColor then
		self.border.Color = borderColor
		self.border.Transparency = 1
		self._hasBorder = true
	else
		self._hasBorder = false
	end
	self:_apply()
end

function Panel:SetRect(x: number, y: number, w: number, h: number)
	self.x, self.y, self.w, self.h = x, y, w, h
	self:_apply()
end

function Panel:_apply()
	local x, y, w, h, r = self.x, self.y, self.w, self.h, self._radius
	if r > 0 and #self.corners == 4 and w > r * 2 and h > r * 2 then
		-- central plus-shape fill leaves the four corners for the circles
		self.fill.Position = Vector2.new(x + r, y)
		self.fill.Size     = Vector2.new(w - 2 * r, h)
		-- a second horizontal band drawn by re-using border? Instead use corners +
		-- we approximate body with one tall square + side fills via corners overlap.
		-- For a clean look we expand fill to cover middle, and add side strips:
		self.corners[1].Position = Vector2.new(x + r, y + r)             -- TL
		self.corners[2].Position = Vector2.new(x + w - r, y + r)         -- TR
		self.corners[3].Position = Vector2.new(x + r, y + h - r)         -- BL
		self.corners[4].Position = Vector2.new(x + w - r, y + h - r)     -- BR
		-- left/right strips: re-purpose border-less behaviour by widening fill bands
		-- (we keep it simple: corners + central square + two thin side squares)
		if not self._sideL then
			self._sideL = mk("Square", { Filled = true, Thickness = 0, ZIndex = self.zBase })
			self._sideR = mk("Square", { Filled = true, Thickness = 0, ZIndex = self.zBase })
		end
		self._sideL.Color, self._sideL.Transparency = self.fill.Color, self.fill.Transparency
		self._sideR.Color, self._sideR.Transparency = self.fill.Color, self.fill.Transparency
		self._sideL.Position = Vector2.new(x, y + r)
		self._sideL.Size     = Vector2.new(r, h - 2 * r)
		self._sideR.Position = Vector2.new(x + w - r, y + r)
		self._sideR.Size     = Vector2.new(r, h - 2 * r)
		if self._visible then
			self._sideL.Visible = true; self._sideR.Visible = true
		end
	else
		self.fill.Position = Vector2.new(x, y)
		self.fill.Size     = Vector2.new(w, h)
		if self._sideL then self._sideL.Visible = false; self._sideR.Visible = false end
	end
	self.border.Position = Vector2.new(x, y)
	self.border.Size     = Vector2.new(w, h)
	self.border.Visible  = self._visible and self._hasBorder
end

function Panel:SetZ(z: number)
	self.zBase = z
	self.fill.ZIndex = z
	self.border.ZIndex = z + 1
	for _, c in ipairs(self.corners) do c.ZIndex = z end
	if self._sideL then self._sideL.ZIndex = z; self._sideR.ZIndex = z end
end

function Panel:SetVisible(v: boolean)
	self._visible = v
	self.fill.Visible = v
	self.border.Visible = v and self._hasBorder
	for _, c in ipairs(self.corners) do c.Visible = v end
	if self._sideL and (self._radius <= 0) then
		self._sideL.Visible = false; self._sideR.Visible = false
	elseif self._sideL then
		self._sideL.Visible = v; self._sideR.Visible = v
	end
end

function Panel:Destroy()
	destroyDrawing(self.fill)
	destroyDrawing(self.border)
	if self._sideL then destroyDrawing(self._sideL); destroyDrawing(self._sideR) end
	for _, c in ipairs(self.corners) do destroyDrawing(c) end
	self.corners = {}
end

-- ============================================================================
--  PRIMITIVE: Label text helper
-- ============================================================================
local function newText(z: number, center: boolean?): any
	return mk("Text", {
		Text = "", Size = T().FontSize, Color = T().Text,
		Center = center or false, Outline = true,
		OutlineColor = Color3.new(0, 0, 0), Font = T().Font, ZIndex = z,
	})
end

-- ============================================================================
--  COMPONENT BASE
--  Provides the standard handle methods + drawing/interactive bookkeeping.
-- ============================================================================
local function newComponent(section: any, name: string, height: number): any
	local c = {
		Name = name,
		section = section,
		window = section and section.tab.window,
		_height = height,
		_drawings = {},
		_panels = {},
		_interactives = {},
		_visible = true,
		_filtered = false, -- hidden by searchbar
		rect = { x = 0, y = 0, w = 0, h = 0 },
	}
	return c
end

-- Convenience constructors that auto-track into a component
local function compText(c: any, z: number, center: boolean?): any
	local t = newText(z, center)
	table.insert(c._drawings, t)
	return t
end
local function compPanel(c: any, z: number): any
	local p = Panel.new(z)
	table.insert(c._panels, p)
	return p
end
local function compInteractive(c: any, obj: any): any
	obj.visible = true
	table.insert(c._interactives, obj)
	addInteractive(obj)
	return obj
end

-- ============================================================================
--  NOTIFICATION SYSTEM
-- ============================================================================
local NOTIFY_W = 300
local function relayoutNotifications()
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1280
	local pad = 12
	local y = 60
	for _, n in ipairs(state.notifications) do
		local targetY = y
		tween(n, "y", n._y or targetY, targetY, 0.25, Ease.OutCubic, function(v)
			n._y = v
			n:_position(vw, v)
		end)
		y += n._h + pad
	end
end

local function createNotification(opts: {[string]: any}): any
	opts = opts or {}
	local th = T()
	local typeColor = ({
		info = th.Info, success = th.Success, warning = th.Warning, error = th.Error,
	})[opts.Type or "info"] or th.Info

	local title   = tostring(opts.Title or "Notification")
	local message = tostring(opts.Message or "")
	local duration = tonumber(opts.Duration) or 4

	local lines = (message ~= "" and 1 or 0)
	local h = 24 + (lines > 0 and 20 or 0) + 16

	local n: any = {}
	n._h = h
	n.panel = Panel.new(Z.Notify)
	n.panel:SetRadius(th.CornerRadius)
	n.panel:SetColors(th.NotificationBackground, th.Border, 1 - th.Transparency)
	n.stripe = mk("Square", { Filled = true, Thickness = 0, Color = typeColor, ZIndex = Z.Notify + 2 })
	n.titleText = mk("Text", { Text = title, Size = th.FontSize, Color = th.Text,
		Font = th.Font, Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.NotifyText })
	n.msgText = mk("Text", { Text = message, Size = th.FontSize - 1, Color = th.SubText,
		Font = th.Font, Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.NotifyText })

	function n:_position(vw: number, y: number)
		local x = self._x or (vw - NOTIFY_W - 16)
		self.panel:SetRect(x, y, NOTIFY_W, self._h)
		self.stripe.Position = Vector2.new(x, y)
		self.stripe.Size = Vector2.new(3, self._h)
		self.titleText.Position = Vector2.new(x + 14, y + 9)
		self.msgText.Position = Vector2.new(x + 14, y + 9 + 20)
	end

	function n:_show(v: boolean)
		self.panel:SetVisible(v)
		self.stripe.Visible = v
		self.titleText.Visible = v
		self.msgText.Visible = v and (message ~= "")
	end

	function n:Destroy()
		for i = #state.notifications, 1, -1 do
			if state.notifications[i] == self then table.remove(state.notifications, i) break end
		end
		self.panel:Destroy()
		destroyDrawing(self.stripe)
		destroyDrawing(self.titleText)
		destroyDrawing(self.msgText)
		relayoutNotifications()
	end

	table.insert(state.notifications, n)

	-- entrance: slide in from the right edge
	local cam = Workspace.CurrentCamera
	local vw = cam and cam.ViewportSize.X or 1280
	n:_show(true)
	n._x = vw + 10
	n:_position(vw, 60)
	relayoutNotifications()
	tween(n, "x", vw + 10, vw - NOTIFY_W - 16, 0.35, Ease.OutCubic, function(v)
		n._x = v
		n:_position(vw, n._y or 60)
	end)

	-- timed exit
	n._dieAt = os.clock() + duration
	return n
end

-- ============================================================================
--  COMPONENT CONSTRUCTORS
--  Each is fully self-contained: builds its drawings, registers interactives,
--  and returns a handle with :Set/:Get/:SetVisible/:Destroy.
-- ============================================================================

-- ---- BUTTON ----------------------------------------------------------------
local function makeButton(section: any, opts: {[string]: any}): any
	assert(type(opts) == "table", "CreateButton: options table expected")
	local c = newComponent(section, tostring(opts.Name or "Button"), 30)
	c.kind = "Button"
	local panel = compPanel(c, Z.Element)
	local label = compText(c, Z.ElementText, true)
	label.Text = c.Name

	local hot = compInteractive(c, { zindex = Z.Element, rect = c.rect })
	c._hot = hot
	local hovering, pressing = false, false

	local function refresh()
		local th = T()
		local fill = th.Foreground
		if pressing then fill = th.Active elseif hovering then fill = th.Hover end
		panel:SetColors(fill, th.Border, 1 - th.Transparency)
		label.Color = th.Text
		label.Size = th.FontSize
	end
	c._refresh = refresh

	hot.onHover = function(v) hovering = v; refresh() end
	hot.onDown = function() pressing = true; refresh() end
	hot.onUp = function(inside)
		pressing = false; refresh()
		if inside and opts.Callback then task.spawn(opts.Callback) end
	end

	function c:Layout(x, y, w)
		self.rect.x, self.rect.y, self.rect.w, self.rect.h = x, y, w, self._height
		panel:SetRadius(T().CornerRadius)
		panel:SetRect(x, y, w, self._height)
		label.Position = Vector2.new(x + w / 2, y + (self._height - label.Size) / 2)
	end
	function c:ApplyTheme() refresh() end
	function c:_setShown(v)
		panel:SetVisible(v); label.Visible = v; hot._enabled = v; hot.visible = v
	end
	function c:Get() return nil end
	function c:Set() end -- buttons have no value
	refresh()
	return c
end

-- ---- LABEL -----------------------------------------------------------------
local function makeLabel(section: any, opts: {[string]: any}): any
	opts = opts or {}
	local c = newComponent(section, "Label", 22)
	c.kind = "Label"
	local label = compText(c, Z.ElementText, false)
	c._value = tostring(opts.Text or opts.Name or "Label")
	label.Text = c._value

	function c:Layout(x, y, w)
		self.rect.x, self.rect.y, self.rect.w, self.rect.h = x, y, w, self._height
		label.Position = Vector2.new(x, y + (self._height - label.Size) / 2)
	end
	function c:ApplyTheme() label.Color = T().SubText; label.Size = T().FontSize end
	function c:_setShown(v) label.Visible = v end
	function c:Get() return c._value end
	function c:Set(text)
		c._value = tostring(text)
		label.Text = c._value
	end
	c:ApplyTheme()
	return c
end

-- ---- TOGGLE ----------------------------------------------------------------
local function makeToggle(section: any, opts: {[string]: any}): any
	assert(type(opts) == "table", "CreateToggle: options table expected")
	local c = newComponent(section, tostring(opts.Name or "Toggle"), 30)
	c.kind = "Toggle"
	c._value = opts.Default == true

	local label = compText(c, Z.ElementText, false)
	label.Text = c.Name
	local track = compPanel(c, Z.Element)
	local knob = mk("Circle", { Filled = true, Thickness = 0, NumSides = 24, ZIndex = Z.Element + 2 })
	table.insert(c._drawings, knob)

	local TRACK_W, TRACK_H = 38, 18
	local hot = compInteractive(c, { zindex = Z.Element, rect = c.rect })
	local hovering = false
	c._knobX = 0

	local function knobTarget(): number
		return c._value and 1 or 0
	end

	local function placeKnob(alpha: number)
		local x = c.rect.x + c.rect.w - TRACK_W
		local y = c.rect.y + (c._height - TRACK_H) / 2
		local r = TRACK_H / 2 - 2
		knob.Radius = r
		knob.Position = Vector2.new(
			Util.lerp(x + r + 2, x + TRACK_W - r - 2, alpha),
			y + TRACK_H / 2)
	end

	local function refresh(animate: boolean?)
		local th = T()
		label.Color, label.Size = th.Text, th.FontSize
		local trackColor = c._value and th.ToggleOn or th.ToggleOff
		if hovering and not c._value then trackColor = th.Hover end
		track:SetColors(trackColor, nil, 1 - th.Transparency)
		knob.Color = c._value and Color3.new(1,1,1) or th.SubText
		if animate then
			tween(c, "knob", c._knobX, knobTarget(), 0.18, Ease.OutCubic, function(v)
				c._knobX = v; placeKnob(v)
			end)
		else
			c._knobX = knobTarget(); placeKnob(c._knobX)
		end
	end
	c._refresh = refresh

	hot.onHover = function(v) hovering = v; refresh() end
	hot.onUp = function(inside)
		if inside then c:Set(not c._value) end
	end

	function c:Layout(x, y, w)
		self.rect.x, self.rect.y, self.rect.w, self.rect.h = x, y, w, self._height
		label.Position = Vector2.new(x, y + (self._height - label.Size) / 2)
		local tx = x + w - TRACK_W
		local ty = y + (self._height - TRACK_H) / 2
		track:SetRadius(TRACK_H / 2)
		track:SetRect(tx, ty, TRACK_W, TRACK_H)
		placeKnob(c._knobX)
	end
	function c:ApplyTheme() refresh() end
	function c:_setShown(v)
		track:SetVisible(v); knob.Visible = v; label.Visible = v
		hot._enabled = v; hot.visible = v
	end
	function c:Get() return c._value end
	function c:Set(v)
		c._value = v and true or false
		refresh(true)
		if opts.Flag and c.window then c.window.Flags[opts.Flag] = c._value end
		if opts.Callback then task.spawn(opts.Callback, c._value) end
	end
	refresh()
	if opts.Flag and c.window then c.window.Flags[opts.Flag] = c._value end
	return c
end

-- ---- SLIDER ----------------------------------------------------------------
local function makeSlider(section: any, opts: {[string]: any}): any
	assert(type(opts) == "table", "CreateSlider: options table expected")
	local min = tonumber(opts.Min) or 0
	local max = tonumber(opts.Max) or 100
	assert(min < max, "Slider: Min must be less than Max")
	local step = tonumber(opts.Step) or 1
	local suffix = tostring(opts.Suffix or "")

	local c = newComponent(section, tostring(opts.Name or "Slider"), 42)
	c.kind = "Slider"
	c._value = Util.snap(tonumber(opts.Default) or min, min, max, step)

	local label = compText(c, Z.ElementText, false)
	label.Text = c.Name
	local valueText = compText(c, Z.ElementText, false)
	local trackBG = compPanel(c, Z.Element)
	local fill = compPanel(c, Z.Element + 2)

	local BAR_H = 6
	local hot = compInteractive(c, { zindex = Z.Element, rect = c.rect })
	local hovering = false

	local function fraction(): number
		return (c._value - min) / (max - min)
	end

	local function refresh()
		local th = T()
		label.Color, label.Size = th.Text, th.FontSize
		valueText.Color, valueText.Size = th.SubText, th.FontSize - 1
		valueText.Text = tostring(c._value) .. suffix
		trackBG:SetColors(th.ToggleOff, nil, 1 - th.Transparency)
		fill:SetColors(th.SliderFill, nil, 1 - th.Transparency)
		-- place fill width
		local r = c.rect
		local barY = r.y + 26
		fill:SetRect(r.x, barY, math.max(BAR_H, r.w * fraction()), BAR_H)
	end
	c._refresh = refresh

	local function setFromX(px: number)
		local r = c.rect
		local f = Util.clamp((px - r.x) / math.max(1, r.w), 0, 1)
		local raw = min + f * (max - min)
		c:Set(Util.snap(raw, min, max, step))
	end

	hot.onHover = function(v) hovering = v end
	hot.onDown = function(px) setFromX(px) end
	hot.onDrag = function(px) setFromX(px) end

	function c:Layout(x, y, w)
		self.rect.x, self.rect.y, self.rect.w, self.rect.h = x, y, w, self._height
		label.Position = Vector2.new(x, y + 2)
		valueText.Position = Vector2.new(x + w - 60, y + 2)
		valueText.Center = false
		local barY = y + 26
		trackBG:SetRadius(BAR_H / 2)
		trackBG:SetRect(x, barY, w, BAR_H)
		fill:SetRadius(BAR_H / 2)
		refresh()
	end
	function c:ApplyTheme() refresh() end
	function c:_setShown(v)
		trackBG:SetVisible(v); fill:SetVisible(v)
		label.Visible = v; valueText.Visible = v
		hot._enabled = v; hot.visible = v
	end
	function c:Get() return c._value end
	function c:Set(v)
		c._value = Util.snap(tonumber(v) or min, min, max, step)
		refresh()
		if opts.Flag and c.window then c.window.Flags[opts.Flag] = c._value end
		if opts.Callback then task.spawn(opts.Callback, c._value) end
	end
	-- right-align the value text
	valueText.Center = false
	refresh()
	if opts.Flag and c.window then c.window.Flags[opts.Flag] = c._value end
	return c
end

-- ---- KEYBIND ---------------------------------------------------------------
local function makeKeybind(section: any, opts: {[string]: any}): any
	assert(type(opts) == "table", "CreateKeybind: options table expected")
	local c = newComponent(section, tostring(opts.Name or "Keybind"), 30)
	c.kind = "Keybind"
	c._value = opts.Default
	c._mode = (opts.Mode == "Hold") and "Hold" or "Toggle"
	c._listening = false
	c._heldState = false

	local label = compText(c, Z.ElementText, false)
	label.Text = c.Name
	local box = compPanel(c, Z.Element)
	local keyText = compText(c, Z.ElementText, true)

	local BOX_W = 84
	local hot = compInteractive(c, { zindex = Z.Element, rect = c.rect })
	local hovering = false

	local function keyName(): string
		if c._listening then return "..." end
		if typeof(c._value) == "EnumItem" then return c._value.Name end
		return "None"
	end

	local function refresh()
		local th = T()
		label.Color, label.Size = th.Text, th.FontSize
		keyText.Text = keyName()
		keyText.Color = c._listening and th.Accent or th.SubText
		keyText.Size = th.FontSize - 1
		box:SetColors(hovering and th.Hover or th.Foreground, th.Border, 1 - th.Transparency)
	end
	c._refresh = refresh

	hot.onHover = function(v) hovering = v; refresh() end
	hot.onUp = function(inside)
		if inside then
			c._listening = true
			state.focused = c -- capture keyboard
			refresh()
		end
	end

	-- called by the global input handler when a key is pressed
	c._onKey = function(input: InputObject)
		if c._listening then
			if input.KeyCode == Enum.KeyCode.Escape then
				c._value = nil
			else
				c._value = input.KeyCode
			end
			c._listening = false
			if state.focused == c then state.focused = nil end
			refresh()
			if opts.Callback then task.spawn(opts.Callback, c._value) end
			return true
		end
		return false
	end
	-- global activation when bound key fires (handled in InputBegan/Ended)
	c._matchKey = function(kc: Enum.KeyCode): boolean
		return typeof(c._value) == "EnumItem" and c._value == kc
	end

	function c:Layout(x, y, w)
		self.rect.x, self.rect.y, self.rect.w, self.rect.h = x, y, w, self._height
		label.Position = Vector2.new(x, y + (self._height - label.Size) / 2)
		local bx = x + w - BOX_W
		local by = y + (self._height - 20) / 2
		box:SetRadius(T().CornerRadius)
		box:SetRect(bx, by, BOX_W, 20)
		keyText.Position = Vector2.new(bx + BOX_W / 2, by + (20 - keyText.Size) / 2)
	end
	function c:ApplyTheme() refresh() end
	function c:_setShown(v)
		box:SetVisible(v); label.Visible = v; keyText.Visible = v
		hot._enabled = v; hot.visible = v
	end
	function c:Get() return c._value end
	function c:Set(v)
		c._value = (typeof(v) == "EnumItem") and v or nil
		refresh()
	end
	refresh()
	return c
end

-- ---- TEXTBOX ---------------------------------------------------------------
local function makeTextbox(section: any, opts: {[string]: any}): any
	assert(type(opts) == "table", "CreateTextbox: options table expected")
	local c = newComponent(section, tostring(opts.Name or "Input"), 30)
	c.kind = "Textbox"
	c._value = tostring(opts.Default or "")
	c._placeholder = tostring(opts.Placeholder or "")
	c._numeric = opts.Numeric == true
	c._caret = #c._value
	c._focused = false
	c._caretVisible = true

	local label = compText(c, Z.ElementText, false)
	label.Text = c.Name
	local hasLabel = c.Name ~= "" and c.Name ~= "Input"
	local box = compPanel(c, Z.Element)
	local fieldText = compText(c, Z.ElementText, false)
	local caret = mk("Line", { Thickness = 1, ZIndex = Z.ElementText + 1 })
	table.insert(c._drawings, caret)

	local hot = compInteractive(c, { zindex = Z.Element, rect = c.rect })
	local hovering = false
	c._boxRect = { x = 0, y = 0, w = 0, h = 0 }

	local function displayText(): string
		if c._value == "" and not c._focused then return c._placeholder end
		return c._value
	end

	local function refresh()
		local th = T()
		label.Color, label.Size = th.Text, th.FontSize
		fieldText.Size = th.FontSize
		fieldText.Text = displayText()
		fieldText.Color = (c._value == "" and not c._focused) and th.SubText or th.Text
		local borderColor = c._focused and th.Accent or th.Border
		box:SetColors(hovering and th.Hover or th.Foreground, borderColor, 1 - th.Transparency)
		caret.Color = th.Accent
		-- caret position
		local b = c._boxRect
		local before = c._value:sub(1, c._caret)
		local measure = mk("Text", { Text = before, Size = th.FontSize, Font = th.Font, Visible = false })
		local cw = measure.TextBounds.X
		destroyDrawing(measure)
		local cx = b.x + 8 + cw
		caret.From = Vector2.new(cx, b.y + 5)
		caret.To = Vector2.new(cx, b.y + b.h - 5)
		caret.Visible = c._focused and c._caretVisible
	end
	c._refresh = refresh

	hot.onHover = function(v) hovering = v; refresh() end
	hot.onUp = function(inside)
		if inside then
			c._focused = true
			c._caret = #c._value
			state.focused = c
			refresh()
		end
	end

	local function commit()
		if opts.Flag and c.window then c.window.Flags[opts.Flag] = c._value end
		if opts.Callback then task.spawn(opts.Callback, c._value) end
	end

	c._blur = function()
		if c._focused then
			c._focused = false
			if state.focused == c then state.focused = nil end
			refresh()
			commit()
		end
	end

	-- keyboard handler
	c._onKey = function(input: InputObject): boolean
		if not c._focused then return false end
		local kc = input.KeyCode
		if kc == Enum.KeyCode.Return or kc == Enum.KeyCode.KeypadEnter then
			c._blur()
			return true
		elseif kc == Enum.KeyCode.Escape then
			c._blur()
			return true
		elseif kc == Enum.KeyCode.Backspace then
			if c._caret > 0 then
				c._value = c._value:sub(1, c._caret - 1) .. c._value:sub(c._caret + 1)
				c._caret -= 1
				refresh()
			end
			return true
		elseif kc == Enum.KeyCode.Left then
			c._caret = math.max(0, c._caret - 1); refresh(); return true
		elseif kc == Enum.KeyCode.Right then
			c._caret = math.min(#c._value, c._caret + 1); refresh(); return true
		end
		local pair = KEY_CHARS[kc]
		if pair then
			local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
				or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
			local ch = shift and pair[2] or pair[1]
			if c._numeric and not ch:match("[%d%.%-]") then return true end
			c._value = c._value:sub(1, c._caret) .. ch .. c._value:sub(c._caret + 1)
			c._caret += 1
			refresh()
			return true
		end
		return false
	end

	function c:Layout(x, y, w)
		self.rect.x, self.rect.y, self.rect.w, self.rect.h = x, y, w, self._height
		local boxW = w
		local boxX = x
		if hasLabel then
			label.Position = Vector2.new(x, y + (self._height - label.Size) / 2)
			boxW = math.min(160, w * 0.5)
			boxX = x + w - boxW
		end
		local by = y + (self._height - 22) / 2
		c._boxRect = { x = boxX, y = by, w = boxW, h = 22 }
		box:SetRadius(T().CornerRadius)
		box:SetRect(boxX, by, boxW, 22)
		fieldText.Position = Vector2.new(boxX + 8, by + (22 - fieldText.Size) / 2)
		refresh()
	end
	function c:ApplyTheme() refresh() end
	function c:_setShown(v)
		box:SetVisible(v); fieldText.Visible = v
		label.Visible = v and hasLabel
		caret.Visible = v and c._focused and c._caretVisible
		hot._enabled = v; hot.visible = v
	end
	function c:Get() return c._value end
	function c:Set(v)
		c._value = tostring(v)
		c._caret = #c._value
		refresh()
		commit()
	end
	refresh()
	return c
end

-- ---- DROPDOWN --------------------------------------------------------------
local function makeDropdown(section: any, opts: {[string]: any}): any
	assert(type(opts) == "table", "CreateDropdown: options table expected")
	assert(type(opts.Options) == "table", "Dropdown: Options must be a table")
	local c = newComponent(section, tostring(opts.Name or "Dropdown"), 30)
	c.kind = "Dropdown"
	c._options = table.clone(opts.Options)
	c._multi = opts.Multi == true
	c._search = opts.Search == true
	c._open = false
	c._scroll = 0
	if c._multi then
		c._value = {}
		if type(opts.Default) == "table" then
			for _, v in ipairs(opts.Default) do c._value[v] = true end
		end
	else
		c._value = opts.Default
	end

	local label = compText(c, Z.ElementText, false)
	label.Text = c.Name
	local field = compPanel(c, Z.Element)
	local valueText = compText(c, Z.ElementText, false)
	local arrow = compText(c, Z.ElementText, true)
	arrow.Text = "v"

	local hot = compInteractive(c, { zindex = Z.Element, rect = c.rect })
	local hovering = false

	-- overlay objects (lazily shown when open)
	c._overlay = { panel = nil, items = {}, search = nil, scrollbar = nil }
	local MAX_VISIBLE = 6
	local ITEM_H = 26

	local function selectedLabel(): string
		if c._multi then
			local list = {}
			for _, opt in ipairs(c._options) do
				if c._value[opt] then table.insert(list, tostring(opt)) end
			end
			if #list == 0 then return "None" end
			return table.concat(list, ", ")
		else
			return c._value ~= nil and tostring(c._value) or "..."
		end
	end

	local function refreshField()
		local th = T()
		label.Color, label.Size = th.Text, th.FontSize
		valueText.Size = th.FontSize
		valueText.Text = selectedLabel()
		valueText.Color = th.SubText
		arrow.Color = th.SubText
		arrow.Size = th.FontSize - 2
		field:SetColors(hovering and th.Hover or th.Foreground,
			c._open and th.Accent or th.Border, 1 - th.Transparency)
	end
	c._refresh = refreshField

	-- forward declarations
	local closeOverlay, openOverlay, buildOverlay, filteredOptions

	function filteredOptions(): {any}
		if not (c._search and c._overlay.search and c._overlay.search._value ~= "") then
			return c._options
		end
		local q = c._overlay.search._value:lower()
		local out = {}
		for _, opt in ipairs(c._options) do
			if tostring(opt):lower():find(q, 1, true) then table.insert(out, opt) end
		end
		return out
	end

	local function overlayRect(): (number, number, number, number)
		local r = c.rect
		local searchH = c._search and (ITEM_H + 4) or 0
		local opts2 = filteredOptions()
		local count = math.min(#opts2, MAX_VISIBLE)
		local h = searchH + count * ITEM_H + 6
		local x = r.x
		local y = r.y + r.h + 4
		return x, y, r.w, h
	end

    function buildOverlay()
		closeOverlay()
		local th = T()
		local ox, oy, ow, oh = overlayRect()
		local panel = Panel.new(Z.Popup)
		panel:SetRadius(th.CornerRadius)
		panel:SetColors(th.DropdownBackground, th.Accent, 1 - th.Transparency)
		panel:SetRect(ox, oy, ow, oh)
		panel:SetVisible(true)
		c._overlay.panel = panel

		local contentY = oy + 3
		if c._search then
			-- a lightweight inline search textbox built directly here
			local sPanel = Panel.new(Z.PopupContent)
			sPanel:SetRadius(th.CornerRadius)
			local sText = mk("Text", { Size = th.FontSize, Font = th.Font, Color = th.Text,
				Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.PopupContent + 1 })
			local sCaret = mk("Line", { Thickness = 1, Color = th.Accent, ZIndex = Z.PopupContent + 2 })
			local search: any = {
				_value = "", _caret = 0, _focused = false, panel = sPanel,
				text = sText, caret = sCaret,
				rect = { x = ox + 4, y = contentY, w = ow - 8, h = ITEM_H },
				zindex = Z.PopupContent, visible = true,
			}
			local function srefresh()
				sPanel:SetColors(th.Foreground, search._focused and th.Accent or th.Border, 1 - th.Transparency)
				sText.Text = (search._value == "" and not search._focused) and "Search..." or search._value
				sText.Color = (search._value == "") and th.SubText or th.Text
				local before = mk("Text", { Text = search._value, Size = th.FontSize, Font = th.Font, Visible = false })
				local cw = before.TextBounds.X
				destroyDrawing(before)
				sCaret.From = Vector2.new(search.rect.x + 6 + cw, search.rect.y + 4)
				sCaret.To = Vector2.new(search.rect.x + 6 + cw, search.rect.y + ITEM_H - 4)
				sCaret.Visible = search._focused and c._caretVisible ~= false
			end
			sPanel:SetRect(search.rect.x, search.rect.y, search.rect.w, search.rect.h)
			sPanel:SetVisible(true)
			sText.Position = Vector2.new(search.rect.x + 6, search.rect.y + (ITEM_H - th.FontSize)/2)
			sText.Visible = true
			search._refresh = srefresh
			search.onUp = function(inside)
				if inside then search._focused = true; state.focused = search; srefresh() end
			end
			search._blur = function() search._focused = false; if state.focused == search then state.focused = nil end; srefresh() end
			search._onKey = function(input)
				if not search._focused then return false end
				local kc = input.KeyCode
				if kc == Enum.KeyCode.Backspace then
					if search._caret > 0 then
						search._value = search._value:sub(1, search._caret-1)..search._value:sub(search._caret+1)
						search._caret -= 1
					end
				elseif kc == Enum.KeyCode.Return or kc == Enum.KeyCode.Escape then
					search._blur()
				else
					local pair = KEY_CHARS[kc]
					if pair then
						local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
						local ch = shift and pair[2] or pair[1]
						search._value = search._value:sub(1, search._caret)..ch..search._value:sub(search._caret+1)
						search._caret += 1
					else
						return true
					end
				end
				srefresh()
				buildOverlay() -- rebuild list with filter (preserves focus below)
				return true
			end
			addInteractive(search)
			c._overlay.search = search
			srefresh()
			contentY += ITEM_H + 4
		end

		local opts2 = filteredOptions()
		local count = math.min(#opts2, MAX_VISIBLE)
		c._scroll = Util.clamp(c._scroll, 0, math.max(0, #opts2 - MAX_VISIBLE))
		for i = 1, count do
			local idx = i + c._scroll
			local opt = opts2[idx]
			if opt == nil then break end
			local iy = contentY + (i - 1) * ITEM_H
			local itemPanel = Panel.new(Z.PopupContent)
			local itemText = mk("Text", { Text = tostring(opt), Size = th.FontSize, Font = th.Font,
				Color = th.Text, Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.PopupContent + 1 })
			local selected = c._multi and c._value[opt] or (c._value == opt)
			local item: any = {
				zindex = Z.PopupContent, visible = true,
				rect = { x = ox + 3, y = iy, w = ow - 6, h = ITEM_H },
				panel = itemPanel, text = itemText, opt = opt,
			}
			local function irefresh(hover: boolean?)
				local sel = c._multi and c._value[opt] or (c._value == opt)
				itemPanel:SetColors(sel and th.AccentDim or (hover and th.Hover or th.DropdownBackground),
					nil, 1 - th.Transparency)
				itemText.Color = sel and th.Text or th.SubText
			end
			itemPanel:SetRadius(0)
			itemPanel:SetRect(item.rect.x, item.rect.y, item.rect.w, item.rect.h)
			itemPanel:SetVisible(true)
			itemText.Position = Vector2.new(item.rect.x + 8, iy + (ITEM_H - th.FontSize)/2)
			itemText.Visible = true
			item.onHover = function(v) irefresh(v) end
			item.onUp = function(inside)
				if not inside then return end
				if c._multi then
					c._value[opt] = (not c._value[opt]) or nil
				else
					c._value = opt
				end
				refreshField()
				if opts.Flag and c.window then c.window.Flags[opts.Flag] = c._value end
				if opts.Callback then task.spawn(opts.Callback, c:Get()) end
				if c._multi then
					buildOverlay() -- keep open, refresh checks
				else
					closeOverlay()
				end
			end
			irefresh(false)
			addInteractive(item)
			table.insert(c._overlay.items, item)
		end

		-- scrollbar
		if #opts2 > MAX_VISIBLE then
			local barX = ox + ow - 5
			local trackH = count * ITEM_H
			local thumbH = trackH * (MAX_VISIBLE / #opts2)
			local thumbY = contentY + (trackH - thumbH) * (c._scroll / math.max(1, #opts2 - MAX_VISIBLE))
			local sb = mk("Square", { Filled = true, Thickness = 0, Color = th.Accent,
				ZIndex = Z.PopupContent + 2 })
			sb.Position = Vector2.new(barX, thumbY)
			sb.Size = Vector2.new(3, thumbH)
			sb.Visible = true
			c._overlay.scrollbar = sb
		end

		state.openPopup = c
	end

	function openOverlay()
		c._open = true
		refreshField()
		buildOverlay()
	end

	function closeOverlay()
		if c._overlay.search then
			if c._overlay.search._blur then c._overlay.search._blur() end
			removeInteractive(c._overlay.search)
			c._overlay.search.panel:Destroy()
			destroyDrawing(c._overlay.search.text)
			destroyDrawing(c._overlay.search.caret)
			c._overlay.search = nil
		end
		for _, item in ipairs(c._overlay.items) do
			removeInteractive(item)
			item.panel:Destroy()
			destroyDrawing(item.text)
		end
		c._overlay.items = {}
		if c._overlay.scrollbar then destroyDrawing(c._overlay.scrollbar); c._overlay.scrollbar = nil end
		if c._overlay.panel then c._overlay.panel:Destroy(); c._overlay.panel = nil end
		if state.openPopup == c then state.openPopup = nil end
	end
	c._closePopup = closeOverlay
	c._scrollPopup = function(delta: number)
		local opts2 = filteredOptions()
		if #opts2 <= MAX_VISIBLE then return end
		c._scroll = Util.clamp(c._scroll + delta, 0, #opts2 - MAX_VISIBLE)
		buildOverlay()
	end

	hot.onHover = function(v) hovering = v; refreshField() end
	hot.onUp = function(inside)
		if not inside then return end
		if c._open then closeOverlay(); c._open = false else openOverlay() end
		refreshField()
	end
	c._fieldHot = hot

	function c:Layout(x, y, w)
		self.rect.x, self.rect.y, self.rect.w, self.rect.h = x, y, w, self._height
		local hasLabel = c.Name ~= "" and c.Name ~= "Dropdown"
		local fieldX, fieldW = x, w
		if hasLabel then
			label.Position = Vector2.new(x, y + 2)
			fieldX, fieldW = x, w
			-- label on top, field below within same row height: put field right side
			label.Position = Vector2.new(x, y + (self._height - label.Size) / 2)
			fieldW = math.min(180, w * 0.55)
			fieldX = x + w - fieldW
		end
		local by = y + (self._height - 22) / 2
		field:SetRadius(T().CornerRadius)
		field:SetRect(fieldX, by, fieldW, 22)
		valueText.Position = Vector2.new(fieldX + 8, by + (22 - valueText.Size) / 2)
		arrow.Position = Vector2.new(fieldX + fieldW - 12, by + 4)
		c._fieldRect = { x = fieldX, y = by, w = fieldW, h = 22 }
		hot.rect = self.rect
		refreshField()
		if c._open then buildOverlay() end
	end
	function c:ApplyTheme() refreshField(); if c._open then buildOverlay() end end
	function c:_setShown(v)
		field:SetVisible(v); valueText.Visible = v; arrow.Visible = v
		label.Visible = v and (c.Name ~= "" and c.Name ~= "Dropdown")
		hot._enabled = v; hot.visible = v
		if not v and c._open then closeOverlay(); c._open = false end
	end
	function c:Get()
		if c._multi then
			local list = {}
			for _, opt in ipairs(c._options) do if c._value[opt] then table.insert(list, opt) end end
			return list
		end
		return c._value
	end
	function c:Set(v)
		if c._multi then
			c._value = {}
			if type(v) == "table" then for _, x in ipairs(v) do c._value[x] = true end end
		else
			c._value = v
		end
		refreshField()
		if c._open then buildOverlay() end
		if opts.Flag and c.window then c.window.Flags[opts.Flag] = c:Get() end
		if opts.Callback then task.spawn(opts.Callback, c:Get()) end
	end
	c.SetOptions = function(_, newOpts)
		c._options = table.clone(newOpts)
		refreshField()
		if c._open then buildOverlay() end
	end
	refreshField()
	return c
end

-- ---- COLOR PICKER ----------------------------------------------------------
local function makeColorPicker(section: any, opts: {[string]: any}): any
	assert(type(opts) == "table", "CreateColorPicker: options table expected")
	local c = newComponent(section, tostring(opts.Name or "Color"), 30)
	c.kind = "ColorPicker"
	c._value = (typeof(opts.Default) == "Color3") and opts.Default or Color3.fromRGB(255, 255, 255)
	c._h, c._s, c._v = c._value:ToHSV()
	c._open = false

	local label = compText(c, Z.ElementText, false)
	label.Text = c.Name
	local swatch = compPanel(c, Z.Element)
	local swatchBorder = swatch -- panel has its own border
	local hot = compInteractive(c, { zindex = Z.Element, rect = c.rect })
	local hovering = false

	c._overlay = nil
	local SV_COLS, SV_ROWS = 16, 12
	local SV_W, SV_H = 180, 130
	local HUE_SEGMENTS = 24

	local function syncValue()
		c._value = Color3.fromHSV(c._h, c._s, c._v)
	end

	local function refreshSwatch()
		local th = T()
		label.Color, label.Size = th.Text, th.FontSize
		swatch:SetColors(c._value, th.Border, 1)
	end
	c._refresh = refreshSwatch

	local closePicker, buildPicker

	function buildPicker()
		if c._overlay then
			-- update existing grid colors/indicators
		end
		closePicker()
		local th = T()
		local r = c.rect
		local px = r.x + r.w - (SV_W + 24)
		px = math.max(8, px)
		local py = r.y + r.h + 4
		local panelW = SV_W + 16
		local panelH = SV_H + 80
		local panel = Panel.new(Z.Popup)
		panel:SetRadius(th.CornerRadius)
		panel:SetColors(th.DropdownBackground, th.Accent, 1 - th.Transparency)
		panel:SetRect(px, py, panelW, panelH)
		panel:SetVisible(true)

		local ov: any = { panel = panel, cells = {}, hueSegs = {}, extras = {} }
		c._overlay = ov

		local svX, svY = px + 8, py + 8
		-- SV field grid
		local cw, ch = SV_W / SV_COLS, SV_H / SV_ROWS
		for col = 0, SV_COLS - 1 do
			for row = 0, SV_ROWS - 1 do
				local sat = col / (SV_COLS - 1)
				local val = 1 - row / (SV_ROWS - 1)
				local cell = mk("Square", { Filled = true, Thickness = 0,
					Color = Color3.fromHSV(c._h, sat, val), ZIndex = Z.PopupContent })
				cell.Position = Vector2.new(svX + col * cw, svY + row * ch)
				cell.Size = Vector2.new(cw + 1, ch + 1)
				cell.Visible = true
				table.insert(ov.cells, cell)
			end
		end
		-- SV selection indicator
		local svInd = mk("Circle", { Filled = false, Thickness = 2, NumSides = 20, Radius = 5,
			Color = Color3.new(1,1,1), ZIndex = Z.PopupContent + 2 })
		svInd.Position = Vector2.new(svX + c._s * SV_W, svY + (1 - c._v) * SV_H)
		svInd.Visible = true
		ov.svInd = svInd

		-- SV interactive
		local svHit: any = {
			zindex = Z.PopupContent, visible = true,
			rect = { x = svX, y = svY, w = SV_W, h = SV_H },
		}
		local function setSV(mx, my)
			c._s = Util.clamp((mx - svX) / SV_W, 0, 1)
			c._v = Util.clamp(1 - (my - svY) / SV_H, 0, 1)
			syncValue(); refreshSwatch()
			svInd.Position = Vector2.new(svX + c._s * SV_W, svY + (1 - c._v) * SV_H)
			if opts.Callback then task.spawn(opts.Callback, c._value) end
		end
		svHit.onDown = function(mx, my) setSV(mx, my) end
		svHit.onDrag = function(mx, my) setSV(mx, my) end
		addInteractive(svHit)
		table.insert(ov.extras, svHit)

		-- Hue bar
		local hueY = svY + SV_H + 8
		local segW = SV_W / HUE_SEGMENTS
		for i = 0, HUE_SEGMENTS - 1 do
			local hh = i / HUE_SEGMENTS
			local seg = mk("Square", { Filled = true, Thickness = 0,
				Color = Color3.fromHSV(hh, 1, 1), ZIndex = Z.PopupContent })
			seg.Position = Vector2.new(svX + i * segW, hueY)
			seg.Size = Vector2.new(segW + 1, 14)
			seg.Visible = true
			table.insert(ov.hueSegs, seg)
		end
		local hueInd = mk("Square", { Filled = false, Thickness = 2, Color = Color3.new(1,1,1),
			ZIndex = Z.PopupContent + 2 })
		hueInd.Size = Vector2.new(4, 16)
		hueInd.Position = Vector2.new(svX + c._h * SV_W - 2, hueY - 1)
		hueInd.Visible = true
		ov.hueInd = hueInd

		local hueHit: any = {
			zindex = Z.PopupContent, visible = true,
			rect = { x = svX, y = hueY, w = SV_W, h = 14 },
		}
		local function setHue(mx)
			c._h = Util.clamp((mx - svX) / SV_W, 0, 1)
			syncValue(); refreshSwatch()
			hueInd.Position = Vector2.new(svX + c._h * SV_W - 2, hueY - 1)
			-- recolor SV grid
			for idx, cell in ipairs(ov.cells) do
				local col = math.floor((idx - 1) / SV_ROWS)
				local row = (idx - 1) % SV_ROWS
				local sat = col / (SV_COLS - 1)
				local val = 1 - row / (SV_ROWS - 1)
				cell.Color = Color3.fromHSV(c._h, sat, val)
			end
			if opts.Callback then task.spawn(opts.Callback, c._value) end
		end
		hueHit.onDown = function(mx) setHue(mx) end
		hueHit.onDrag = function(mx) setHue(mx) end
		addInteractive(hueHit)
		table.insert(ov.extras, hueHit)

		-- Hex input
		local hexY = hueY + 22
		local hexPanel = Panel.new(Z.PopupContent)
		hexPanel:SetRadius(th.CornerRadius)
		hexPanel:SetColors(th.Foreground, th.Border, 1 - th.Transparency)
		local hexLabel = mk("Text", { Text = "#", Size = th.FontSize, Font = th.Font, Color = th.SubText,
			Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.PopupContent + 1 })
		local hexText = mk("Text", { Size = th.FontSize, Font = th.Font, Color = th.Text,
			Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.PopupContent + 1 })
		local hex: any = {
			_value = Util.colorToHex(c._value), _focused = false,
			rect = { x = svX, y = hexY, w = SV_W, h = 22 }, zindex = Z.PopupContent, visible = true,
			panel = hexPanel, text = hexText, hash = hexLabel,
		}
		local function hexRefresh()
			hexPanel:SetColors(th.Foreground, hex._focused and th.Accent or th.Border, 1 - th.Transparency)
			hexText.Text = hex._value
		end
		hexPanel:SetRect(hexY and svX or svX, hexY, SV_W, 22)
		hexPanel:SetRect(svX, hexY, SV_W, 22)
		hexPanel:SetVisible(true)
		hexLabel.Position = Vector2.new(svX + 8, hexY + 4)
		hexText.Position = Vector2.new(svX + 18, hexY + 4)
		hexLabel.Visible = true; hexText.Visible = true
		hex.onUp = function(inside) if inside then hex._focused = true; state.focused = hex; hexRefresh() end end
		hex._blur = function()
			hex._focused = false
			if state.focused == hex then state.focused = nil end
			local col = Util.hexToColor(hex._value)
			if col then
				c._value = col; c._h, c._s, c._v = col:ToHSV(); refreshSwatch()
				if opts.Callback then task.spawn(opts.Callback, c._value) end
			else
				hex._value = Util.colorToHex(c._value)
			end
			hexRefresh()
		end
		hex._onKey = function(input)
			if not hex._focused then return false end
			local kc = input.KeyCode
			if kc == Enum.KeyCode.Backspace then
				hex._value = hex._value:sub(1, #hex._value - 1)
			elseif kc == Enum.KeyCode.Return then
				hex._blur(); return true
			elseif kc == Enum.KeyCode.Escape then
				hex._value = Util.colorToHex(c._value); hex._blur(); return true
			else
				local pair = KEY_CHARS[kc]
				if pair and #hex._value < 6 then
					local ch = pair[1]:upper()
					if ch:match("[0-9A-F]") then hex._value ..= ch end
				end
			end
			hexRefresh()
			return true
		end
		addInteractive(hex)
		ov.hex = hex
		hexRefresh()

		state.openPopup = c
	end

	function closePicker()
		local ov = c._overlay
		if not ov then return end
		if ov.hex then
			if ov.hex._blur and ov.hex._focused then ov.hex._focused = false end
			removeInteractive(ov.hex)
			ov.hex.panel:Destroy()
			destroyDrawing(ov.hex.text); destroyDrawing(ov.hex.hash)
		end
		for _, cell in ipairs(ov.cells) do destroyDrawing(cell) end
		for _, seg in ipairs(ov.hueSegs) do destroyDrawing(seg) end
		for _, e in ipairs(ov.extras) do removeInteractive(e) end
		if ov.svInd then destroyDrawing(ov.svInd) end
		if ov.hueInd then destroyDrawing(ov.hueInd) end
		ov.panel:Destroy()
		c._overlay = nil
		if state.openPopup == c then state.openPopup = nil end
	end
	c._closePopup = closePicker

	hot.onHover = function(v) hovering = v; refreshSwatch() end
	hot.onUp = function(inside)
		if not inside then return end
		if c._open then closePicker(); c._open = false
		else c._open = true; buildPicker() end
	end
	c._fieldHot = hot

	function c:Layout(x, y, w)
		self.rect.x, self.rect.y, self.rect.w, self.rect.h = x, y, w, self._height
		label.Position = Vector2.new(x, y + (self._height - label.Size) / 2)
		local sw = 36
		local sx = x + w - sw
		local sy = y + (self._height - 18) / 2
		swatch:SetRadius(T().CornerRadius)
		swatch:SetRect(sx, sy, sw, 18)
		hot.rect = self.rect
		refreshSwatch()
		if c._open then buildPicker() end
	end
	function c:ApplyTheme() refreshSwatch(); if c._open then buildPicker() end end
	function c:_setShown(v)
		swatch:SetVisible(v); label.Visible = v
		hot._enabled = v; hot.visible = v
		if not v and c._open then closePicker(); c._open = false end
	end
	function c:Get() return c._value end
	function c:Set(col)
		if typeof(col) ~= "Color3" then error("ColorPicker:Set expects a Color3") end
		c._value = col
		c._h, c._s, c._v = col:ToHSV()
		refreshSwatch()
		if c._open then buildPicker() end
		if opts.Flag and c.window then c.window.Flags[opts.Flag] = c._value end
		if opts.Callback then task.spawn(opts.Callback, c._value) end
	end
	refreshSwatch()
	return c
end

-- ---- SEARCHBAR (filters its section's elements) ----------------------------
local function makeSearchbar(section: any, opts: {[string]: any}): any
	opts = opts or {}
	local box = makeTextbox(section, {
		Name = "", Placeholder = opts.Placeholder or "Search...",
		Callback = nil,
	})
	box.kind = "Searchbar"
	-- override on-key to live-filter
	local baseOnKey = box._onKey
	box._onKey = function(input)
		local handled = baseOnKey(input)
		if handled then
			section:_applyFilter(box._value)
		end
		return handled
	end
	return box
end

-- ============================================================================
--  SECTION
-- ============================================================================
local Section = {}
Section.__index = Section

local function newSection(tab: any, name: string): any
	local self = setmetatable({}, Section)
	self.tab = tab
	self.window = tab.window
	self.Name = name
	self.elements = {}
	self.panel = Panel.new(Z.Content)
	self.header = mk("Text", { Size = T().FontSize, Font = T().Font, Color = T().SubText,
		Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.Content + 2 })
	self.header.Text = name:upper()
	self._visible = false
	registerThemed(self)
	return self
end

local function addElement(section: any, comp: any)
	table.insert(section.elements, comp)
	comp.section = section
	comp.window = section.window
	section.window:_relayout()
	return comp
end

function Section:CreateButton(o)      return addElement(self, makeButton(self, o)) end
function Section:CreateToggle(o)      return addElement(self, makeToggle(self, o)) end
function Section:CreateSlider(o)      return addElement(self, makeSlider(self, o)) end
function Section:CreateDropdown(o)    return addElement(self, makeDropdown(self, o)) end
function Section:CreateTextbox(o)     return addElement(self, makeTextbox(self, o)) end
function Section:CreateLabel(o)       return addElement(self, makeLabel(self, o)) end
function Section:CreateKeybind(o)     return addElement(self, makeKeybind(self, o)) end
function Section:CreateColorPicker(o) return addElement(self, makeColorPicker(self, o)) end
function Section:CreateInput(o)       return self:CreateTextbox(o) end
function Section:CreateSearchbar(o)   return addElement(self, makeSearchbar(self, o)) end

function Section:_applyFilter(query: string)
	query = (query or ""):lower()
	for _, el in ipairs(self.elements) do
		if el.kind ~= "Searchbar" then
			el._filtered = (query ~= "" and not el.Name:lower():find(query, 1, true))
		end
	end
	self.window:_relayout()
end

-- returns consumed height
function Section:Layout(x: number, y: number, w: number): number
	local th = T()
	local pad = th.Padding
	local headerH = th.FontSize + 6
	local innerX = x + pad
	local innerW = w - pad * 2
	local cy = y + headerH + pad

	for _, el in ipairs(self.elements) do
		local shown = el._visible and not el._filtered
		if shown then
			el:Layout(innerX, cy, innerW)
			el:_setShown(self._visible)
			cy += el._height + pad
		else
			el:_setShown(false)
		end
	end
	local totalH = (cy - y) + pad - (#self.elements > 0 and 0 or pad)
	if totalH < headerH + pad * 2 then totalH = headerH + pad * 2 end

	self._rect = { x = x, y = y, w = w, h = totalH }
	self.panel:SetRadius(th.CornerRadius)
	self.panel:SetColors(th.Background, th.Border, 1 - th.Transparency)
	self.panel:SetRect(x, y, w, totalH)
	self.header.Position = Vector2.new(x + pad, y + 4)
	return totalH
end

function Section:SetVisible(v: boolean)
	self._visible = v
	self.panel:SetVisible(v)
	self.header.Visible = v
	for _, el in ipairs(self.elements) do
		el:_setShown(v and el._visible and not el._filtered)
	end
end

function Section:ApplyTheme()
	self.header.Color = T().SubText
	self.header.Size = T().FontSize
	for _, el in ipairs(self.elements) do
		if el.ApplyTheme then el:ApplyTheme() end
	end
end

function Section:Destroy()
	for _, el in ipairs(self.elements) do
		if el.Destroy then el:Destroy() end
	end
	self.elements = {}
	self.panel:Destroy()
	destroyDrawing(self.header)
	unregisterThemed(self)
	for i = #self.tab.sections, 1, -1 do
		if self.tab.sections[i] == self then table.remove(self.tab.sections, i) break end
	end
	self.window:_relayout()
end

-- component-level Destroy (shared) ------------------------------------------
local function componentDestroy(el: any)
	if el._closePopup then el._closePopup() end
	for _, d in ipairs(el._drawings) do destroyDrawing(d) end
	for _, p in ipairs(el._panels) do p:Destroy() end
	for _, hot in ipairs(el._interactives) do removeInteractive(hot) end
	el._drawings, el._panels, el._interactives = {}, {}, {}
	-- remove from section
	if el.section then
		for i = #el.section.elements, 1, -1 do
			if el.section.elements[i] == el then table.remove(el.section.elements, i) break end
		end
		el.section.window:_relayout()
	end
end

-- attach generic handle methods to every component returned above
local function finalizeComponent(el: any)
	el.SetVisible = function(_, v)
		el._visible = v and true or false
		el.section.window:_relayout()
	end
	el.Destroy = el.Destroy or function() componentDestroy(el) end
	local realDestroy = el.Destroy
	el.Destroy = function()
		if el._destroyed then return end
		el._destroyed = true
		componentDestroy(el)
	end
end

-- ============================================================================
--  TAB
-- ============================================================================
local Tab = {}
Tab.__index = Tab

local function newTab(window: any, name: string): any
	local self = setmetatable({}, Tab)
	self.window = window
	self.Name = name
	self.sections = {}
	-- tab button visuals
	self.btnPanel = Panel.new(Z.WindowChrome)
	self.btnText = mk("Text", { Size = T().FontSize, Font = T().Font, Center = true,
		Color = T().SubText, Outline = true, OutlineColor = Color3.new(0,0,0),
		ZIndex = Z.WindowChrome + 2 })
	self.btnText.Text = name
	self.btnRect = { x = 0, y = 0, w = 0, h = 0 }
	self._hover = false

	self.btnHot = {
		zindex = Z.WindowChrome, rect = self.btnRect, visible = true,
		onHover = function(v) self._hover = v; self:_refreshButton() end,
		onUp = function(inside) if inside then window:SelectTab(self) end end,
	}
	addInteractive(self.btnHot)
	registerThemed(self)
	return self
end

function Tab:CreateSection(name: string): any
	local s = newSection(self, tostring(name or "Section"))
	table.insert(self.sections, s)
	self.window:_relayout()
	return s
end

function Tab:_refreshButton()
	local th = T()
	local active = self.window.activeTab == self
	self.btnText.Color = active and th.Text or (self._hover and th.Text or th.SubText)
	self.btnText.Size = th.FontSize
	if active then
		self.btnPanel:SetColors(th.Foreground, nil, 1 - th.Transparency)
	elseif self._hover then
		self.btnPanel:SetColors(th.Hover, nil, 1 - th.Transparency)
	else
		self.btnPanel:SetColors(th.Background, nil, 1 - th.Transparency)
	end
end

function Tab:ApplyTheme()
	self:_refreshButton()
	for _, s in ipairs(self.sections) do s:ApplyTheme() end
end

function Tab:SetVisible(v: boolean)
	for _, s in ipairs(self.sections) do s:SetVisible(v) end
end

function Tab:Destroy()
	for _, s in ipairs(self.sections) do s:Destroy() end
	self.sections = {}
	self.btnPanel:Destroy()
	destroyDrawing(self.btnText)
	removeInteractive(self.btnHot)
	unregisterThemed(self)
	for i = #self.window.tabs, 1, -1 do
		if self.window.tabs[i] == self then table.remove(self.window.tabs, i) break end
	end
	if self.window.activeTab == self then
		self.window.activeTab = self.window.tabs[1]
	end
	self.window:_relayout()
end

-- ============================================================================
--  WINDOW
-- ============================================================================
local Window = {}
Window.__index = Window

local TITLE_H = 32
local TABBAR_H = 30

local function newWindow(opts: {[string]: any}): any
	opts = opts or {}
	local self = setmetatable({}, Window)
	self.Title = tostring(opts.Title or "Window")
	self.Flags = {}
	self.tabs = {}
	self.activeTab = nil
	self._collapsed = false
	self._visible = true

	local size = opts.Size or Vector2.new(520, 420)
	self.size = Vector2.new(math.max(280, size.X), math.max(180, size.Y))
	local cam = Workspace.CurrentCamera
	local vps = cam and cam.ViewportSize or Vector2.new(1280, 720)
	self.pos = opts.Position or Vector2.new(
		(vps.X - self.size.X) / 2, (vps.Y - self.size.Y) / 2)

	-- shadow (layered offset squares)
	self.shadow = {}
	for i = 1, 4 do
		self.shadow[i] = mk("Square", { Filled = true, Thickness = 0,
			Color = T().WindowShadow, ZIndex = Z.Shadow })
	end

	self.bg = Panel.new(Z.WindowBG)
	self.titlebar = Panel.new(Z.WindowChrome)
	self.titleText = mk("Text", { Size = T().FontSize + 1, Font = T().Font, Color = T().Text,
		Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.WindowChrome + 2 })
	self.titleText.Text = self.Title

	-- close & collapse buttons
	self.closeText = mk("Text", { Text = "X", Size = T().FontSize + 2, Font = T().Font, Center = true,
		Color = T().SubText, Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.WindowChrome + 2 })
	self.collapseText = mk("Text", { Text = "-", Size = T().FontSize + 4, Font = T().Font, Center = true,
		Color = T().SubText, Outline = true, OutlineColor = Color3.new(0,0,0), ZIndex = Z.WindowChrome + 2 })

	-- resize grip
	self.grip = {}
	for i = 1, 3 do
		self.grip[i] = mk("Line", { Thickness = 1, Color = T().SubText, ZIndex = Z.WindowChrome + 2 })
	end

	-- ---- interactives -----------------------------------------------------
	self._dragHot = {
		zindex = Z.WindowChrome, rect = { x = 0, y = 0, w = 0, h = 0 }, visible = true,
	}
	do
		local dragging, ox, oy = false, 0, 0
		self._dragHot.onDown = function(mx, my)
			dragging = true; ox = mx - self.pos.X; oy = my - self.pos.Y
		end
		self._dragHot.onDrag = function(mx, my)
			if dragging then
				self.pos = Vector2.new(mx - ox, my - oy)
				self:_relayout()
			end
		end
		self._dragHot.onUp = function() dragging = false end
	end
	addInteractive(self._dragHot)

	self._closeHot = {
		zindex = Z.WindowChrome + 1, rect = { x=0,y=0,w=0,h=0 }, visible = true,
		onHover = function(v) self.closeText.Color = v and T().Error or T().SubText end,
		onUp = function(inside) if inside then self:Destroy() end end,
	}
	addInteractive(self._closeHot)

	self._collapseHot = {
		zindex = Z.WindowChrome + 1, rect = { x=0,y=0,w=0,h=0 }, visible = true,
		onHover = function(v) self.collapseText.Color = v and T().Text or T().SubText end,
		onUp = function(inside) if inside then self:_setCollapsed(not self._collapsed) end end,
	}
	addInteractive(self._collapseHot)

	self._resizeHot = {
		zindex = Z.WindowChrome + 1, rect = { x=0,y=0,w=0,h=0 }, visible = true,
	}
	do
		local resizing, sx, sy = false, 0, 0
		self._resizeHot.onDown = function(mx, my)
			resizing = true; sx = mx - self.size.X; sy = my - self.size.Y
		end
		self._resizeHot.onDrag = function(mx, my)
			if resizing then
				self.size = Vector2.new(
					math.max(280, mx - sx), math.max(180, my - sy))
				self:_relayout()
			end
		end
		self._resizeHot.onUp = function() resizing = false end
	end
	addInteractive(self._resizeHot)

	registerThemed(self)
	table.insert(state.windows, self)
	return self
end

function Window:CreateTab(name: string): any
	local tab = newTab(self, tostring(name or "Tab"))
	table.insert(self.tabs, tab)
	if not self.activeTab then self.activeTab = tab end
	self:_relayout()
	return tab
end

function Window:SelectTab(nameOrTab)
	local target = nameOrTab
	if type(nameOrTab) == "string" then
		for _, t in ipairs(self.tabs) do if t.Name == nameOrTab then target = t break end end
	end
	if target then
		-- close any open popup when switching tabs
		if state.openPopup and state.openPopup._closePopup then
			state.openPopup._closePopup()
			state.openPopup._open = false
		end
		self.activeTab = target
		self:_relayout()
	end
end

function Window:_setCollapsed(v: boolean)
	self._collapsed = v
	self.collapseText.Text = v and "+" or "-"
	self:_relayout()
end

function Window:Toggle()
	self:SetVisible(not self._visible)
end

function Window:SetTitle(t: string)
	self.Title = tostring(t)
	self.titleText.Text = self.Title
end

function Window:SetVisible(v: boolean)
	self._visible = v
	self:_relayout()
end

function Window:_relayout()
	if state.destroyed then return end
	local th = T()
	local vis = self._visible
	local x, y = self.pos.X, self.pos.Y
	local w, h = self.size.X, self.size.Y
	if self._collapsed then h = TITLE_H end

	-- shadow: faint layered halo (Drawing Transparency is alpha; small = subtle)
	for i, s in ipairs(self.shadow) do
		local spread = i * 3
		s.Color = th.WindowShadow
		s.Transparency = 0.16 - (i - 1) * 0.03
		s.Position = Vector2.new(x - spread, y - spread + 4)
		s.Size = Vector2.new(w + spread * 2, h + spread * 2)
		s.Visible = vis
	end

	-- background
	self.bg:SetRadius(th.CornerRadius)
	self.bg:SetColors(th.Background, th.Border, 1 - th.Transparency)
	self.bg:SetRect(x, y, w, h)
	self.bg:SetVisible(vis)

	-- titlebar
	self.titlebar:SetRadius(th.CornerRadius)
	self.titlebar:SetColors(th.Foreground, nil, 1 - th.Transparency)
	self.titlebar:SetRect(x, y, w, TITLE_H)
	self.titlebar:SetVisible(vis)
	self.titleText.Color = th.Text
	self.titleText.Size = th.FontSize + 1
	self.titleText.Position = Vector2.new(x + 12, y + (TITLE_H - self.titleText.Size) / 2)
	self.titleText.Visible = vis

	-- buttons
	local closeSize = 22
	local cx = x + w - closeSize - 6
	self.closeText.Position = Vector2.new(cx + closeSize/2, y + (TITLE_H - self.closeText.Size)/2)
	self.closeText.Visible = vis
	self._closeHot.rect = { x = cx, y = y, w = closeSize, h = TITLE_H }
	self._closeHot._enabled = vis

	local colX = cx - closeSize
	self.collapseText.Position = Vector2.new(colX + closeSize/2, y + (TITLE_H - self.collapseText.Size)/2 - 2)
	self.collapseText.Visible = vis
	self._collapseHot.rect = { x = colX, y = y, w = closeSize, h = TITLE_H }
	self._collapseHot._enabled = vis

	-- drag area (titlebar minus the buttons)
	self._dragHot.rect = { x = x, y = y, w = colX - x, h = TITLE_H }
	self._dragHot._enabled = vis

	-- tabs + content shown only when not collapsed
	local showBody = vis and not self._collapsed

	-- tab bar
	local tabY = y + TITLE_H
	local tabX = x + 6
	for _, tab in ipairs(self.tabs) do
		local tw = math.max(60, (tab.btnText.TextBounds.X or 0) + 24)
		tab.btnRect.x, tab.btnRect.y, tab.btnRect.w, tab.btnRect.h = tabX, tabY + 3, tw, TABBAR_H - 6
		tab.btnHot.rect = tab.btnRect
		tab.btnHot._enabled = showBody
		tab.btnPanel:SetRadius(th.CornerRadius)
		tab.btnPanel:SetRect(tabX, tabY + 3, tw, TABBAR_H - 6)
		tab.btnPanel:SetVisible(showBody)
		tab.btnText.Position = Vector2.new(tabX + tw/2, tabY + 3 + (TABBAR_H - 6 - tab.btnText.Size)/2)
		tab.btnText.Visible = showBody
		tab:_refreshButton()
		tabX += tw + 4
	end

	-- content area: only the active tab's sections
	local contentY = tabY + TABBAR_H + th.Padding
	local contentX = x + th.Padding
	local contentW = w - th.Padding * 2
	for _, tab in ipairs(self.tabs) do
		local isActive = (tab == self.activeTab) and showBody
		if isActive then
			local cy = contentY
			for _, sec in ipairs(tab.sections) do
				sec._visible = true
				local sh = sec:Layout(contentX, cy, contentW)
				sec:SetVisible(true)
				cy += sh + th.Padding
			end
		else
			tab:SetVisible(false)
		end
	end

	-- resize grip (bottom-right)
	local gx, gy = x + w, y + h
	for i, line in ipairs(self.grip) do
		local off = i * 4
		line.From = Vector2.new(gx - off, gy - 2)
		line.To = Vector2.new(gx - 2, gy - off)
		line.Color = th.SubText
		line.Visible = showBody
	end
	self._resizeHot.rect = { x = gx - 16, y = gy - 16, w = 16, h = 16 }
	self._resizeHot._enabled = showBody
end

function Window:ApplyTheme()
	for _, tab in ipairs(self.tabs) do tab:ApplyTheme() end
	self:_relayout()
end

function Window:Destroy()
	for _, tab in ipairs(self.tabs) do tab:Destroy() end
	self.tabs = {}
	self.bg:Destroy()
	self.titlebar:Destroy()
	for _, s in ipairs(self.shadow) do destroyDrawing(s) end
	for _, g in ipairs(self.grip) do destroyDrawing(g) end
	destroyDrawing(self.titleText)
	destroyDrawing(self.closeText)
	destroyDrawing(self.collapseText)
	removeInteractive(self._dragHot)
	removeInteractive(self._closeHot)
	removeInteractive(self._collapseHot)
	removeInteractive(self._resizeHot)
	unregisterThemed(self)
	for i = #state.windows, 1, -1 do
		if state.windows[i] == self then table.remove(state.windows, i) break end
	end
end

-- patch element Create* to finalize handle methods -------------------------
do
	local origAdd = addElement
	-- finalizeComponent attaches SetVisible/Destroy once
	-- we wrap addElement via Section methods already calling addElement;
	-- ensure finalize is applied:
	for _, mname in ipairs({
		"CreateButton","CreateToggle","CreateSlider","CreateDropdown","CreateTextbox",
		"CreateLabel","CreateKeybind","CreateColorPicker","CreateSearchbar",
	}) do
		local orig = Section[mname]
		Section[mname] = function(selfSec, o)
			local el = orig(selfSec, o)
			finalizeComponent(el)
			return el
		end
	end
end

-- ============================================================================
--  GLOBAL INPUT + RENDER LOOP
-- ============================================================================
-- Some executors render Drawing objects in a coordinate space offset from
-- UserInputService:GetMouseLocation() by the topbar GUI inset. If clicks land
-- ~36px off vertically, set Library.MouseOffset = Vector2.new(0, 36) (or -36).
Library.MouseOffset = Vector2.new(0, 0)
local function mousePos(): (number, number)
	local p = UserInputService:GetMouseLocation()
	local off = Library.MouseOffset or Vector2.zero
	return p.X + off.X, p.Y + off.Y
end

local function setupInput()
	-- InputBegan: mouse down -> capture; keys -> focus / keybinds
	table.insert(state.connections, UserInputService.InputBegan:Connect(function(input, gpe)
		if state.destroyed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mx, my = mousePos()
			local target = pick(mx, my)

			-- Close an open popup if the click landed outside its panel and was
			-- not on the field that owns it (the field's own onUp toggles it).
			if state.openPopup then
				local pop = state.openPopup
				local insidePanel = false
				if pop._overlay and pop._overlay.panel then
					local pr = pop._overlay.panel
					insidePanel = Util.pointInRect(mx, my, pr.x, pr.y, pr.w, pr.h)
				end
				if (not insidePanel) and target ~= pop._fieldHot then
					if pop._closePopup then pop._closePopup() end
					pop._open = false
				end
			end

			-- blur a focused textbox when clicking elsewhere
			if state.focused and state.focused ~= target then
				if state.focused._blur then state.focused._blur() end
			end

			if target then
				state.captured = target
				if target.onDown then target.onDown(mx, my) end
			end
		elseif input.UserInputType == Enum.UserInputType.Keyboard then
			-- a focused element (textbox / hex / search) consumes keys first
			if state.focused and state.focused._onKey then
				if state.focused._onKey(input) then return end
			end
			-- otherwise dispatch the press to any matching keybind
			for _, win in ipairs(state.windows) do
				for _, tab in ipairs(win.tabs) do
					for _, sec in ipairs(tab.sections) do
						for _, el in ipairs(sec.elements) do
							if el.kind == "Keybind" and el._matchKey
								and el._matchKey(input.KeyCode) and el._onActivate then
								el._onActivate(true)
							end
						end
					end
				end
			end
		end
	end))

	-- InputChanged: mouse movement -> hover + drag
	table.insert(state.connections, UserInputService.InputChanged:Connect(function(input)
		if state.destroyed then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			local mx, my = mousePos()
			if state.captured then
				if state.captured.onDrag then state.captured.onDrag(mx, my) end
			else
				local target = pick(mx, my)
				if target ~= state.hovered then
					if state.hovered and state.hovered.onHover then state.hovered.onHover(false) end
					state.hovered = target
					if target and target.onHover then target.onHover(true) end
				end
			end
		elseif input.UserInputType == Enum.UserInputType.MouseWheel then
			-- scroll the open dropdown popup
			if state.openPopup and state.openPopup._scrollPopup then
				state.openPopup._scrollPopup(-input.Position.Z)
			end
		end
	end))

	-- InputEnded: release capture
	table.insert(state.connections, UserInputService.InputEnded:Connect(function(input)
		if state.destroyed then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local mx, my = mousePos()
			if state.captured then
				local cap = state.captured
				local inside = cap.rect and Util.pointInRect(mx, my, cap.rect.x, cap.rect.y, cap.rect.w, cap.rect.h)
				state.captured = nil
				if cap.onUp then cap.onUp(inside) end
			end
		elseif input.UserInputType == Enum.UserInputType.Keyboard then
			-- hold-mode keybinds release
			for _, win in ipairs(state.windows) do
				for _, tab in ipairs(win.tabs) do
					for _, sec in ipairs(tab.sections) do
						for _, el in ipairs(sec.elements) do
							if el.kind == "Keybind" and el._mode == "Hold"
								and el._matchKey and el._matchKey(input.KeyCode) then
								if el._onActivate then el._onActivate(false) end
							end
						end
					end
				end
			end
		end
	end))
end

-- give keybinds a unified activation that respects mode + callback
do
	local origMakeKeybind = makeKeybind
	makeKeybind = function(section, opts)
		local c = origMakeKeybind(section, opts)
		c._mode = (opts.Mode == "Hold") and "Hold" or "Toggle"
		c._active = false
		c._onActivate = function(down: boolean)
			if c._mode == "Hold" then
				c._active = down
				if opts.Callback then task.spawn(opts.Callback, down) end
			else
				if down then
					c._active = not c._active
					if opts.Callback then task.spawn(opts.Callback, c._active) end
				end
			end
		end
		return c
	end
end

local function startRender()
	local blinkTimer = 0
	state.renderConn = RunService.RenderStepped:Connect(function(dt)
		if state.destroyed then return end
		stepTweens(dt)

		-- caret blink
		blinkTimer += dt
		if blinkTimer >= 0.5 then
			blinkTimer = 0
			state._caretOn = not state._caretOn
			if state.focused then
				state.focused._caretVisible = state._caretOn
				if state.focused._refresh then state.focused._refresh() end
				if state.focused._onKey then
					-- textbox refresh handled via _refresh; dropdown search & hex
					-- use their own caret toggling:
				end
				if state.focused.panel and state.focused.text then
					-- inline search / hex: toggle caret line visibility
					if state.focused.caret then
						state.focused.caret.Visible = state.focused._focused and state._caretOn
					end
				end
			end
		end

		-- age notifications
		local now = os.clock()
		for i = #state.notifications, 1, -1 do
			local n = state.notifications[i]
			if n._dieAt and now >= n._dieAt and not n._dying then
				n._dying = true
				local cam = Workspace.CurrentCamera
				local vw = cam and cam.ViewportSize.X or 1280
				tween(n, "x", n._x or vw, vw + 20, 0.3, Ease.InQuad, function(v)
					n._x = v; n:_position(vw, n._y or 60)
				end, function()
					n:Destroy()
				end)
			end
		end
	end)
end

-- handle viewport resize -> relayout everything
do
	local cam = Workspace.CurrentCamera
	if cam then
		table.insert(state.connections, cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			for _, w in ipairs(state.windows) do w:_relayout() end
			relayoutNotifications()
		end))
	end
end

setupInput()
startRender()

-- ============================================================================
--  PUBLIC LIBRARY API
-- ============================================================================
function Library:CreateWindow(opts)
	assert(not state.destroyed, "Library has been destroyed")
	if opts and opts.Theme then
		if type(opts.Theme) == "string" then
			self:SetTheme(opts.Theme)
		elseif type(opts.Theme) == "table" then
			self:SetTheme(opts.Theme)
		end
	end
	local w = newWindow(opts)
	w:_relayout()
	return w
end

function Library:SetTheme(themeOrName)
	if type(themeOrName) == "string" then
		local preset = THEMES[themeOrName]
		assert(preset, "SetTheme: unknown theme '" .. tostring(themeOrName) .. "'")
		state.theme = Util.merge(state.theme, preset)
	elseif type(themeOrName) == "table" then
		state.theme = Util.merge(state.theme, themeOrName)
	else
		error("SetTheme expects a theme name or table")
	end
	-- hot-swap: re-apply to every registered themed object
	for _, obj in ipairs(state.themed) do
		if obj.ApplyTheme then obj:ApplyTheme() end
	end
	for _, w in ipairs(state.windows) do w:_relayout() end
	return self
end

function Library:GetTheme()
	return Util.merge(state.theme)
end

function Library:RegisterTheme(name, themeTable)
	assert(type(name) == "string", "RegisterTheme: name must be a string")
	assert(type(themeTable) == "table", "RegisterTheme: theme must be a table")
	THEMES[name] = Util.merge(THEMES.Dark, themeTable)
	return self
end

function Library:Notify(opts)
	assert(not state.destroyed, "Library has been destroyed")
	return createNotification(opts)
end

function Library:Destroy()
	if state.destroyed then return end
	state.destroyed = true
	-- destroy windows (and their elements)
	for i = #state.windows, 1, -1 do
		local ok = pcall(function() state.windows[i]:Destroy() end)
	end
	-- destroy notifications
	for i = #state.notifications, 1, -1 do
		pcall(function() state.notifications[i]:Destroy() end)
	end
	-- disconnect connections
	for _, conn in ipairs(state.connections) do
		pcall(function() conn:Disconnect() end)
	end
	if state.renderConn then pcall(function() state.renderConn:Disconnect() end) end
	-- remove any stray drawings
	for d in pairs(state.drawings) do
		pcall(function() d:Remove() end)
	end
	-- clear state
	state.drawings = {}
	state.connections = {}
	state.tweens = {}
	state.interactives = {}
	state.themed = {}
	state.windows = {}
	state.notifications = {}
	state.captured, state.hovered, state.focused, state.openPopup = nil, nil, nil, nil
end

-- Expose easing & color utilities for advanced users
Library.Util = Util
Library.Ease = Ease
Library.Themes = THEMES

return setmetatable({}, {
	__index = Library,
	__newindex = function(_, k, v) Library[k] = v end,
	__metatable = "Locked",
})
