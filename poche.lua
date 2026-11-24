-- poche
-- a drum machine for your pocket
--
-- E1 sound   E2 step   E3 knob A
-- K1+E3 knob B
-- K2 write the step
-- hold K2: E2/E3 lock A/B on it
-- K3 play / stop
-- K1+E1 effect   K1+E2 pattern
-- hold K1, hold K3: punch effect
-- K1+K2 clear the sound
--
-- grid (optional): rows 1-7
-- sounds, row 8 effects,
-- page, play

engine.name = "Poche"

local musicutil = require "musicutil"

local DATA = _path.data .. "poche/"

-- Sixteen sounds on fourteen voices. `pitched` is the octave offset from
-- the root for the three that play notes; their knob A is a scale degree.
local SOUNDS = {
  { name = "kick",     voice = 1,  a = 0.45, b = 0.50, level = 0.9,  pan = 0,     send = 0 },
  { name = "boom",     voice = 1,  a = 0.12, b = 0.90, level = 0.9,  pan = 0,     send = 0 },
  { name = "snare",    voice = 2,  a = 0.50, b = 0.45, level = 0.8,  pan = 0,     send = 0.1 },
  { name = "clap",     voice = 3,  a = 0.50, b = 0.50, level = 0.75, pan = 0.1,   send = 0.15 },
  { name = "hat",      voice = 4,  a = 0.50, b = 0.30, level = 0.6,  pan = -0.2,  send = 0 },
  { name = "open hat", voice = 5,  a = 0.50, b = 0.45, level = 0.55, pan = -0.2,  send = 0.1 },
  { name = "rim",      voice = 6,  a = 0.50, b = 0.30, level = 0.6,  pan = 0.3,   send = 0.35 },
  { name = "tom low",  voice = 7,  a = 0.20, b = 0.50, level = 0.75, pan = -0.3,  send = 0.1 },
  { name = "tom high", voice = 7,  a = 0.65, b = 0.45, level = 0.7,  pan = 0.3,   send = 0.1 },
  { name = "cowbell",  voice = 8,  a = 0.50, b = 0.40, level = 0.5,  pan = 0.2,   send = 0.2 },
  { name = "shaker",   voice = 9,  a = 0.30, b = 0.30, level = 0.5,  pan = 0.35,  send = 0 },
  { name = "zap",      voice = 10, a = 0.50, b = 0.40, level = 0.55, pan = -0.35, send = 0.4 },
  { name = "bass",     voice = 11, a = 0.00, b = 0.45, level = 0.8,  pan = 0,     send = 0,    pitched = -12 },
  { name = "lead",     voice = 12, a = 0.50, b = 0.35, level = 0.55, pan = 0.15,  send = 0.35, pitched = 12 },
  { name = "stab",     voice = 13, a = 0.28, b = 0.40, level = 0.6,  pan = -0.1,  send = 0.3,  pitched = 0 },
  { name = "sweep",    voice = 14, a = 0.50, b = 0.50, level = 0.5,  pan = 0,     send = 0.3 },
}
local NSOUNDS = #SOUNDS
local NSTEPS = 16
local NPATTERNS = 16
local DEGREES = 15 -- two octaves and one note of the scale

-- Punched in while held; the pattern keeps its place underneath.
local FX = {
  "repeat 4", "repeat 2", "roll", "ratchet 3", "reverse", "half speed",
  "octave up", "octave down", "low-pass", "high-pass", "crush", "echo throw", "scatter",
}

local ECHO_DIVS = { { "1/8", 0.5 }, { "3/16", 0.75 }, { "1/4", 1 }, { "3/8", 1.5 } }

local patterns = {}
local knobs = {}
local current, queued = 1, nil
local sel, cursor = 1, 1
local pos, playhead = 1, 0
local playing = false
local seq_clock = nil
local fx, fx_on, fx_tick, fx_anchor = 1, false, 0, 1
local held = { false, false, false }
local k2_turned, k2_cleared, k3_fx = false, false, false
local flash = {}
local mascot = { squash = 0, mouth = 0, arms = 0, flap = 0, bob = 0, blink = 0, foot = 1, rings = {} }
local beat = 0
local started, intro_until = 0, 0
local scale_names = {}
local notes = {}
local message, message_until = nil, 0
local redraw_metro = nil
local g = grid.connect()

-- ---------------------------------------------------------------- data

local function empty_pattern()
  local p = {}
  for s = 1, NSOUNDS do
    p[s] = {}
    for i = 1, NSTEPS do p[s][i] = false end
  end
  return p
end

local function deg(d) return d / (DEGREES - 1) end

-- Two patterns to start from, so K3 plays something the first time.
local function demo()
  for p = 1, NPATTERNS do patterns[p] = empty_pattern() end
  local function put(p, s, steps, locks)
    for n, i in ipairs(steps) do
      patterns[p][s][i] = locks and locks[n] or {}
    end
  end
  -- 1: four to the floor, open hats on the off-beat, a bass that answers
  put(1, 1, { 1, 5, 9, 13 })
  put(1, 4, { 5, 13 })
  put(1, 5, { 2, 4, 6, 8, 10, 12, 14, 16 }, {
    { b = 0.2 }, { b = 0.2 }, { b = 0.25 }, { b = 0.2 }, { b = 0.2 }, { b = 0.2 }, { b = 0.3 }, { b = 0.2 },
  })
  put(1, 6, { 3, 7, 11, 15 })
  put(1, 7, { 12 })
  put(1, 11, { 1, 3, 5, 7, 9, 11, 13, 15 })
  put(1, 13, { 3, 4, 7, 11, 12, 15 }, {
    { a = deg(0) }, { a = deg(5) }, { a = deg(0) }, { a = deg(3) }, { a = deg(2) }, { a = deg(4) },
  })
  -- 2: a broken beat, a stab and a little lead
  put(2, 1, { 1, 4, 11 })
  put(2, 2, { 7 })
  put(2, 3, { 5, 13 })
  put(2, 5, { 1, 3, 5, 7, 9, 11, 13, 15 })
  put(2, 6, { 16 })
  put(2, 7, { 8, 15 })
  put(2, 12, { 10 })
  put(2, 13, { 1, 4, 9, 11, 14 }, {
    { a = deg(0) }, { a = deg(0) }, { a = deg(3) }, { a = deg(5) }, { a = deg(2) },
  })
  put(2, 14, { 3, 6, 9, 12, 14 }, {
    { a = deg(7) }, { a = deg(9) }, { a = deg(10) }, { a = deg(9) }, { a = deg(7) },
  })
  put(2, 15, { 1, 7 }, { { a = deg(0) }, { a = deg(3) } })
end

local function reset_knobs()
  for s = 1, NSOUNDS do knobs[s] = { a = SOUNDS[s].a, b = SOUNDS[s].b } end
end

local function save_state(path)
  util.make_dir(DATA)
  tab.save({ patterns = patterns, knobs = knobs, current = current }, path)
end

local function load_state(path)
  if not util.file_exists(path) then return false end
  local t = tab.load(path)
  if type(t) ~= "table" or type(t.patterns) ~= "table" then return false end
  for p = 1, NPATTERNS do
    patterns[p] = empty_pattern()
    local src = t.patterns[p]
    if type(src) == "table" then
      for s = 1, NSOUNDS do
        if type(src[s]) == "table" then
          for i = 1, NSTEPS do
            local st = src[s][i]
            if type(st) == "table" then patterns[p][s][i] = { a = st.a, b = st.b } end
          end
        end
      end
    end
  end
  if type(t.knobs) == "table" then
    for s = 1, NSOUNDS do
      if type(t.knobs[s]) == "table" then
        knobs[s] = { a = t.knobs[s].a or SOUNDS[s].a, b = t.knobs[s].b or SOUNDS[s].b }
      end
    end
  end
  current = util.clamp(tonumber(t.current) or 1, 1, NPATTERNS)
  return true
end

-- ---------------------------------------------------------------- sound

local function build_notes()
  local name = scale_names[params:get("scale")]
  local root = params:get("root")
  for s = 1, NSOUNDS do
    local off = SOUNDS[s].pitched
    if off then notes[s] = musicutil.generate_scale(root + off, name, 4) end
  end
end

local function degree_of(a) return util.clamp(math.floor(a * (DEGREES - 1) + 0.5), 0, DEGREES - 1) end

local function note_of(s, a, octave)
  local list = notes[s]
  return list[degree_of(a) + 1] + (octave or 0)
end

local function fx_is(name) return fx_on and FX[fx] == name end

-- What poche does when it hears each kind of sound.
local function react(s)
  local v = SOUNDS[s].voice
  if v == 1 then
    mascot.squash = 3
  elseif v == 2 then
    mascot.mouth = 6
  elseif v == 3 then
    mascot.mouth, mascot.arms = 6, 6
  elseif v == 5 then
    mascot.flap = 4
  end
end

local function sound(s, a, b, amp_scale)
  local snd = SOUNDS[s]
  local amp = params:get("level_" .. s) * (amp_scale or 1)
  if amp <= 0 then return end
  local send = params:get("send_" .. s)
  if fx_is("echo throw") then send = 1 end
  local va = a
  if snd.pitched then
    local octave = 0
    if fx_is("octave up") then octave = 12 elseif fx_is("octave down") then octave = -12 end
    va = musicutil.note_num_to_freq(note_of(s, a, octave))
  end
  engine.hit(snd.voice, amp, va, b, params:get("pan_" .. s), send)
  flash[s] = 15
  react(s)
end

local function trigger(s, i, amp_scale)
  local st = patterns[current][s][i]
  if not st then return end
  sound(s, st.a or knobs[s].a, st.b or knobs[s].b, amp_scale)
end

-- Heard while editing, so a knob can be set by ear with the machine stopped.
local function audition(s, i)
  if playing then return end
  local st = i and patterns[current][s][i] or nil
  local a = (st and st.a) or knobs[s].a
  local b = (st and st.b) or knobs[s].b
  sound(s, a, b)
end

-- ---------------------------------------------------------------- effects

local function master_defaults()
  engine.filt(params:get("filter"))
  engine.crush(params:get("crush"))
  engine.dfb(params:get("echo_fb"))
end

local function set_fx(on)
  if on then
    fx_on, fx_tick = true, 0
    local name = FX[fx]
    if name == "repeat 4" then fx_anchor = pos - ((pos - 1) % 4)
    elseif name == "repeat 2" then fx_anchor = pos - ((pos - 1) % 2)
    else fx_anchor = pos end
    if name == "low-pass" then engine.filt(-0.82)
    elseif name == "high-pass" then engine.filt(0.62)
    elseif name == "crush" then engine.crush(0.7)
    elseif name == "echo throw" then engine.dfb(0.62) end
  else
    fx_on = false
    master_defaults()
  end
end

-- Which step this tick plays, and how many times.
local function which_step()
  if not fx_on then return pos, 1 end
  local name = FX[fx]
  local k = fx_tick
  fx_tick = fx_tick + 1
  if name == "repeat 4" then return (fx_anchor - 1 + k % 4) % NSTEPS + 1, 1
  elseif name == "repeat 2" then return (fx_anchor - 1 + k % 2) % NSTEPS + 1, 1
  elseif name == "roll" then return fx_anchor, 2
  elseif name == "ratchet 3" then return pos, 3
  elseif name == "reverse" then return NSTEPS + 1 - pos, 1
  elseif name == "half speed" then
    return (fx_anchor - 1 + math.floor(k / 2)) % NSTEPS + 1, (k % 2 == 0) and 1 or 0
  elseif name == "scatter" then return math.random(NSTEPS), 1
  end
  return pos, 1
end

-- ---------------------------------------------------------------- the sequencer

local function step_sec() return clock.get_beat_sec() / 4 end

local function update_echo()
  engine.dtime(clock.get_beat_sec() * ECHO_DIVS[params:get("echo_div")][2])
end

local function play(i, n)
  if n <= 0 then return end
  if n == 1 then
    for s = 1, NSOUNDS do trigger(s, i) end
    return
  end
  clock.run(function()
    local d = step_sec() / n
    for r = 1, n do
      for s = 1, NSOUNDS do trigger(s, i, r == 1 and 1 or 0.7) end
      if r < n then clock.sleep(d) end
    end
  end)
end

local function run()
  while true do
    clock.sync(1 / 4)
    local swing = params:get("swing") / 100
    if pos % 2 == 0 and swing > 0 then clock.sleep(step_sec() * swing) end
    local i, n = which_step()
    playhead = i
    if (pos - 1) % 4 == 0 then
      beat = math.floor((pos - 1) / 4) + 1
      mascot.bob = 1
      mascot.foot = 3 - mascot.foot
      if fx_is("echo throw") then mascot.rings[#mascot.rings + 1] = { r = 3, life = 1 } end
    end
    play(i, n)
    pos = pos % NSTEPS + 1
    if pos == 1 then
      if queued then current, queued = queued, nil end
      update_echo()
    end
  end
end

local function start()
  if playing then return end
  pos, playing = 1, true
  update_echo()
  seq_clock = clock.run(run)
end

local function stop()
  if seq_clock then clock.cancel(seq_clock) end
  seq_clock, playing, playhead = nil, false, 0
  if queued then current, queued = queued, nil end
end

local function toggle_play()
  if playing then stop() else start() end
end

local function say(text)
  message, message_until = text, util.time() + 1.2
end

-- ---------------------------------------------------------------- controls

local function knob_delta(s, which, d, st)
  local target = st or knobs[s]
  local base = target[which] or knobs[s][which]
  if which == "a" and SOUNDS[s].pitched then
    target.a = deg(util.clamp(degree_of(base) + d, 0, DEGREES - 1))
  else
    target[which] = util.clamp(base + d * 0.02, 0, 1)
  end
end

function enc(n, d)
  if n == 1 then
    if held[1] then
      fx = util.clamp(fx + d, 1, #FX)
      if fx_on then set_fx(true) end
      say(FX[fx])
    else
      sel = util.clamp(sel + d, 1, NSOUNDS)
    end
  elseif n == 2 then
    if held[2] then
      local st = patterns[current][sel][cursor] or {}
      patterns[current][sel][cursor] = st
      knob_delta(sel, "a", d, st)
      k2_turned = true
      audition(sel, cursor)
    elseif held[1] then
      local p = util.clamp((queued or current) + d, 1, NPATTERNS)
      if playing then queued = (p ~= current) and p or nil else current = p end
    else
      cursor = (cursor - 1 + d) % NSTEPS + 1
    end
  elseif n == 3 then
    if held[2] then
      local st = patterns[current][sel][cursor] or {}
      patterns[current][sel][cursor] = st
      knob_delta(sel, "b", d, st)
      k2_turned = true
      audition(sel, cursor)
    else
      knob_delta(sel, held[1] and "b" or "a", d)
      audition(sel)
    end
  end
end

function key(n, z)
  held[n] = (z == 1)
  if n == 2 then
    if z == 1 then
      k2_turned, k2_cleared = false, false
      if held[1] then
        for i = 1, NSTEPS do patterns[current][sel][i] = false end
        k2_cleared = true
        say("cleared " .. SOUNDS[sel].name)
      end
    elseif not k2_turned and not k2_cleared then
      if patterns[current][sel][cursor] then
        patterns[current][sel][cursor] = false
      else
        patterns[current][sel][cursor] = {}
        audition(sel, cursor)
      end
    end
  elseif n == 3 then
    if z == 1 then
      if held[1] then
        k3_fx = true
        set_fx(true)
      else
        toggle_play()
      end
    elseif k3_fx then
      k3_fx = false
      set_fx(false)
    end
  end
end

-- ---------------------------------------------------------------- grid

local function grid_page() return math.floor((sel - 1) / 7) end

local function grid_redraw()
  g:all(0)
  local page = grid_page()
  for r = 1, 7 do
    local s = page * 7 + r
    if s <= NSOUNDS then
      for i = 1, NSTEPS do
        local on = patterns[current][s][i]
        local lvl = on and 9 or (s == sel and 2 or 0)
        if playing and i == playhead then lvl = on and 15 or math.max(lvl, 4) end
        g:led(i, r, lvl)
      end
    end
  end
  for i = 1, #FX do g:led(i, 8, (fx_on and i == fx) and 15 or (i == fx and 6 or 2)) end
  g:led(15, 8, 3 + page * 5)
  g:led(16, 8, playing and 15 or 4)
  g:refresh()
end

g.key = function(x, y, z)
  if y <= 7 then
    local s = grid_page() * 7 + y
    if z == 1 and s <= NSOUNDS then
      sel = s
      if patterns[current][s][x] then
        patterns[current][s][x] = false
      else
        patterns[current][s][x] = {}
        audition(s, x)
      end
    end
  elseif x <= #FX then
    if z == 1 then
      fx = x
      set_fx(true)
    elseif fx == x then
      set_fx(false)
    end
  elseif x == 15 and z == 1 then
    sel = ((grid_page() + 1) % 3) * 7 + 1
  elseif x == 16 and z == 1 then
    toggle_play()
  end
end

-- ---------------------------------------------------------------- screen

local function value_text(s, which, v)
  if which == "a" and SOUNDS[s].pitched then
    return musicutil.note_num_to_name(note_of(s, v), true)
  end
  return tostring(math.floor(v * 99 + 0.5))
end

local function now_s() return util.time() - started end

local function line(...)
  local pts = { ... }
  screen.move(pts[1], pts[2])
  for i = 3, #pts, 2 do screen.line(pts[i], pts[i + 1]) end
  screen.stroke()
end

-- Each sound's own little picture, eight pixels square.
local ICONS = {
  function(x, y) -- kick: the front of a bass drum
    screen.move(x + 7.5, y + 3.5)
    screen.circle(x + 3.5, y + 3.5, 3.5)
    screen.stroke()
    screen.rect(x + 3, y + 3, 2, 2)
    screen.fill()
  end,
  function(x, y) -- boom: the same, all skin
    screen.move(x + 7.5, y + 3.5)
    screen.circle(x + 3.5, y + 3.5, 3.6)
    screen.fill()
    screen.level(0)
    screen.rect(x + 3, y + 3, 2, 2)
    screen.fill()
  end,
  function(x, y) -- snare: a drum with its wires
    screen.rect(x, y + 1, 8, 6)
    screen.fill()
    screen.level(0)
    for k = 0, 3 do screen.rect(x + 1 + k * 2, y + 3 + (k % 2), 1, 1) end
    screen.fill()
  end,
  function(x, y) -- clap: two hands meeting
    line(x + 1.5, y + 7.5, x + 3.5, y + 1.5)
    line(x + 6.5, y + 7.5, x + 4.5, y + 1.5)
    screen.rect(x + 3, y, 2, 1)
    screen.fill()
  end,
  function(x, y) -- hat: two cymbals closed on a stand
    line(x, y + 3.5, x + 8, y + 3.5)
    line(x + 1, y + 4.5, x + 7, y + 4.5)
    line(x + 3.5, y + 4.5, x + 3.5, y + 8)
  end,
  function(x, y) -- open hat: the same, apart
    line(x, y + 1.5, x + 8, y + 1.5)
    line(x + 1, y + 5.5, x + 7, y + 5.5)
    line(x + 3.5, y + 1.5, x + 3.5, y + 8)
  end,
  function(x, y) -- rim: a stick on an edge
    screen.move(x + 4.5, y + 4.5)
    screen.circle(x + 2.5, y + 4.5, 2)
    screen.stroke()
    line(x + 3.5, y + 4.5, x + 7.5, y + 0.5)
  end,
  function(x, y) -- tom low: a deep drum
    screen.rect(x, y + 2, 8, 6)
    screen.fill()
    screen.level(0)
    screen.rect(x + 1, y + 3, 6, 1)
    screen.fill()
  end,
  function(x, y) -- tom high: a small one
    screen.rect(x + 1, y + 1, 6, 4)
    screen.fill()
    screen.level(0)
    screen.rect(x + 2, y + 2, 4, 1)
    screen.fill()
  end,
  function(x, y) -- cowbell
    screen.move(x + 2, y)
    screen.line(x + 6, y)
    screen.line(x + 8, y + 8)
    screen.line(x, y + 8)
    screen.close()
    screen.fill()
  end,
  function(x, y) -- shaker: an egg full of seeds
    screen.move(x + 7, y + 4)
    screen.circle(x + 4, y + 4, 3)
    screen.fill()
    screen.level(0)
    screen.rect(x + 3, y + 3, 1, 1)
    screen.rect(x + 5, y + 5, 1, 1)
    screen.fill()
  end,
  function(x, y) -- zap
    line(x + 5.5, y, x + 2.5, y + 4.5, x + 5.5, y + 4.5, x + 2.5, y + 8)
  end,
  function(x, y) -- bass: a slow square wave
    line(x, y + 6.5, x + 2.5, y + 6.5, x + 2.5, y + 2.5, x + 5.5, y + 2.5, x + 5.5, y + 6.5, x + 8, y + 6.5)
  end,
  function(x, y) -- lead: a quick one
    line(x, y + 4.5, x + 1.5, y + 4.5, x + 1.5, y + 1.5, x + 3.5, y + 1.5, x + 3.5, y + 4.5,
      x + 5.5, y + 4.5, x + 5.5, y + 1.5, x + 8, y + 1.5)
  end,
  function(x, y) -- stab: a chord, three notes stacked
    for k = 0, 2 do screen.rect(x + 2, y + 1 + k * 2, 6, 1) end
    screen.rect(x, y + 1, 1, 5)
    screen.fill()
  end,
  function(x, y) -- sweep: a rising rush
    line(x, y + 7.5, x + 3, y + 6.5, x + 5, y + 4.5, x + 6.5, y + 2, x + 7.5, y)
  end,
}

local function pattern_has(p)
  for s = 1, NSOUNDS do
    for i = 1, NSTEPS do
      if patterns[p][s][i] then return true end
    end
  end
  return false
end

local function pad_xy(i)
  return 1 + ((i - 1) % 4) * 12, 11 + math.floor((i - 1) / 4) * 12
end

-- A key with a little depth: lit from the top left.
local function pad(x, y, on, here, locked)
  if on then
    screen.level(here and 15 or 9)
    screen.rect(x, y, 10, 10)
    screen.fill()
    screen.level(here and 15 or 13)
    line(x + 0.5, y + 9, x + 0.5, y + 0.5, x + 9.5, y + 0.5)
    screen.level(here and 10 or 5)
    line(x + 9.5, y + 1, x + 9.5, y + 9.5, x + 1, y + 9.5)
    if locked then
      screen.level(0)
      screen.rect(x + 6, y + 2, 2, 2)
      screen.fill()
    end
  else
    screen.level(here and 5 or 1)
    screen.rect(x, y, 10, 10)
    screen.fill()
    screen.level(here and 9 or 3)
    line(x + 0.5, y + 9, x + 0.5, y + 0.5, x + 9.5, y + 0.5)
  end
end

local function brackets(x, y, w, h, d)
  local x0, y0, x1, y1 = x - d + 0.5, y - d + 0.5, x + w + d - 0.5, y + h + d - 0.5
  line(x0, y0 + 3, x0, y0, x0 + 3, y0)
  line(x1 - 3, y0, x1, y0, x1, y0 + 3)
  line(x1, y1 - 3, x1, y1, x1 - 3, y1)
  line(x0 + 3, y1, x0, y1, x0, y1 - 3)
end

local function draw_header()
  screen.level(15)
  screen.rect(0, 0, 19, 8)
  screen.fill()
  screen.level(0)
  screen.move(2, 6)
  screen.text(string.format("P%02d", current))
  if queued and math.floor(now_s() * 4) % 2 == 0 then
    screen.level(10)
    screen.move(22, 6)
    screen.text(string.format(">%02d", queued))
  end
  -- play, and which way
  local px, py = 45, 1
  screen.level(playing and 15 or 5)
  if not playing then
    screen.rect(px, py, 5, 5)
  elseif fx_is("reverse") then
    screen.move(px + 5, py)
    screen.line(px + 5, py + 6)
    screen.line(px, py + 3)
    screen.close()
  else
    screen.move(px, py)
    screen.line(px, py + 6)
    screen.line(px + 5, py + 3)
    screen.close()
  end
  screen.fill()
  -- the four beats of the bar
  for b = 1, 4 do
    screen.level((playing and b == beat) and 15 or 3)
    screen.rect(54 + (b - 1) * 5, 2, 3, 3)
    screen.fill()
  end
  screen.level(playing and 15 or 5)
  screen.move(127, 6)
  screen.text_right(string.format("%d", math.floor(clock.get_tempo() + 0.5)))
  screen.level(3)
  screen.move(127 - screen.text_extents(string.format("%d", math.floor(clock.get_tempo() + 0.5))) - 3, 6)
  screen.text_right("bpm")
end

local function draw_steps()
  local t = now_s()
  local jitter = fx_is("scatter")
  for i = 1, NSTEPS do
    local x, y = pad_xy(i)
    if jitter then x, y = x + math.random(-1, 1), y + math.random(-1, 1) end
    local st = patterns[current][sel][i]
    pad(x, y, st, playing and i == playhead, st and (st.a or st.b))
  end
  -- the loop an effect is holding
  local len = fx_is("repeat 4") and 4 or fx_is("repeat 2") and 2 or fx_is("roll") and 1 or 0
  if len > 0 and math.floor(t * 8) % 2 == 0 then
    local x, y = pad_xy(fx_anchor)
    screen.level(15)
    screen.rect(x - 1.5, y - 1.5, 12 * len + 1, 13)
    screen.stroke()
  end
  local x, y = pad_xy(cursor)
  screen.level(15)
  brackets(x, y, 10, 10, 1 + math.floor((math.sin(t * 6) + 1) * 0.6))
end

-- While K1 is held: the sixteen patterns, which have something in them,
-- which is playing and which is next.
local function draw_patterns()
  local blink = math.floor(now_s() * 4) % 2 == 0
  for p = 1, NPATTERNS do
    local x, y = pad_xy(p)
    local has = pattern_has(p)
    screen.level(p == current and 13 or (has and 4 or 1))
    screen.rect(x, y, 10, 10)
    screen.fill()
    if p == queued and blink then
      screen.level(15)
      screen.rect(x - 0.5, y - 0.5, 11, 11)
      screen.stroke()
    end
    screen.level(p == current and 0 or (has and 15 or 5))
    screen.move(x + 5, y + 7)
    screen.text_center(tostring(p))
  end
end

local function draw_sound()
  screen.level(15)
  ICONS[sel](54, 10)
  screen.level(15)
  screen.move(65, 17)
  screen.text(SOUNDS[sel].name)
  -- every sound, jumping as it plays
  for s = 1, NSOUNDS do
    local x = 54 + (s - 1) * 3
    local h = math.floor((flash[s] or 0) / 15 * 6 + 0.5)
    screen.level(s == sel and 7 or 2)
    screen.rect(x, 27, 2, 1)
    screen.fill()
    if h > 0 then
      screen.level(s == sel and 15 or 9)
      screen.rect(x, 27 - h, 2, h)
      screen.fill()
    end
  end
end

local function dial(x, y, v, label, text, locked, arrow)
  local a0 = math.pi * 0.75
  screen.aa(1)
  screen.line_width(1)
  screen.level(2)
  screen.move(x + math.cos(a0) * 7, y + math.sin(a0) * 7)
  screen.arc(x, y, 7, a0, a0 + math.pi * 1.5)
  screen.stroke()
  screen.line_width(2)
  screen.level(locked and 15 or 11)
  screen.move(x + math.cos(a0) * 7, y + math.sin(a0) * 7)
  screen.arc(x, y, 7, a0, a0 + math.pi * 1.5 * math.max(0.02, v))
  screen.stroke()
  screen.line_width(1)
  local ae = a0 + math.pi * 1.5 * v
  screen.level(15)
  screen.move(x + math.cos(ae) * 7 + 1.5, y + math.sin(ae) * 7)
  screen.circle(x + math.cos(ae) * 7, y + math.sin(ae) * 7, 1.5)
  screen.fill()
  screen.aa(0)
  screen.level(locked and 15 or 9)
  screen.move(x, y + 3)
  screen.text_center(text)
  screen.level(locked and 9 or 3)
  screen.move(x, y + 14)
  screen.text_center(locked and "lock" or label)
  if arrow then
    screen.level(15)
    screen.move(x + 7, y - 4 + (arrow > 0 and 3 or 0))
    screen.line(x + 11, y - 4 + (arrow > 0 and 3 or 0))
    screen.line(x + 9, y - 4 + (arrow > 0 and 0 or 3))
    screen.close()
    screen.fill()
  end
end

local function draw_knobs()
  local st = held[2] and patterns[current][sel][cursor] or nil
  local a = (st and st.a) or knobs[sel].a
  local b = (st and st.b) or knobs[sel].b
  local pitched = SOUNDS[sel].pitched ~= nil
  local arrow = nil
  if pitched and fx_is("octave up") then arrow = 1 elseif pitched and fx_is("octave down") then arrow = -1 end
  dial(64, 40, a, pitched and "note" or "tone", value_text(sel, "a", a), st and st.a ~= nil, arrow)
  dial(88, 40, b, pitched and "shape" or "decay", value_text(sel, "b", b), st and st.b ~= nil)
end

-- poche itself: a pocket with a flap, eyes, arms and feet. It dances on
-- the beat, ducks for the kick, sings with the snare, throws its arms up for
-- a clap, lifts its flap for an open hat, and sleeps when nothing plays.
local function draw_mascot(cx, base, awake)
  awake = awake or playing
  local t = now_s()
  local m = mascot
  local bob = awake and math.floor(m.bob * 2 + 0.5) or 0
  local w = 18 + math.floor(m.squash)
  local h = 16 - math.floor(m.squash)
  local x, top = cx - w / 2, base - h - bob
  -- feet, one up and one down
  screen.level(5)
  local up = awake and m.foot or 0
  screen.rect(cx - 6, base - (up == 1 and 1 or 0), 4, 2)
  screen.rect(cx + 2, base - (up == 2 and 1 or 0), 4, 2)
  screen.fill()
  -- arms
  screen.level(7)
  local swing = awake and (m.foot == 1 and 1 or -1) or 0
  local lift = m.arms > 0 and -6 or 2
  line(x + 0.5, top + 9.5, x - 3.5, top + 9.5 + lift + swing)
  line(x + w - 0.5, top + 9.5, x + w + 3.5, top + 9.5 + lift - swing)
  -- the body, with its seam
  screen.level(6)
  screen.rect(x, top, w, h)
  screen.fill()
  screen.level(0)
  screen.rect(x, top, 1, 1)
  screen.rect(x + w - 1, top, 1, 1)
  screen.rect(x, top + h - 1, 1, 1)
  screen.rect(x + w - 1, top + h - 1, 1, 1)
  screen.fill()
  screen.level(3)
  for k = x + 2, x + w - 3, 2 do screen.rect(k, top + h - 2, 1, 1) end
  screen.fill()
  -- the flap
  local lift_flap = math.floor(m.flap)
  screen.level(10)
  screen.move(x - 1, top - lift_flap)
  screen.line(x + w + 1, top)
  screen.line(x + w - 2, top + 4)
  screen.line(x + 2, top + 4 - lift_flap)
  screen.close()
  screen.fill()
  screen.level(4)
  screen.rect(cx - 1, top + 2, 2, 2)
  screen.fill()
  -- eyes
  local ey = top + 6
  if not awake then
    screen.level(9)
    screen.rect(cx - 6, ey + 1, 4, 1)
    screen.rect(cx + 2, ey + 1, 4, 1)
    screen.fill()
    local zt = (t * 0.8) % 1
    screen.level(math.floor(12 * (1 - zt)))
    screen.move(cx + 8 + zt * 4, top - 2 - zt * 8)
    screen.text("z")
  elseif fx_is("crush") then
    screen.level(15)
    line(cx - 6, ey, cx - 3, ey + 3)
    line(cx - 6, ey + 3, cx - 3, ey)
    line(cx + 2, ey, cx + 5, ey + 3)
    line(cx + 2, ey + 3, cx + 5, ey)
  elseif m.blink > 0 then
    screen.level(15)
    screen.rect(cx - 6, ey + 1, 4, 1)
    screen.rect(cx + 2, ey + 1, 4, 1)
    screen.fill()
  else
    screen.level(15)
    screen.rect(cx - 6, ey, 4, 4)
    screen.rect(cx + 2, ey, 4, 4)
    screen.fill()
    -- it watches the cursor
    local lx = ((cursor - 1) % 4) - 1.5
    local ly = math.floor((cursor - 1) / 4) - 1.5
    if fx_is("reverse") then lx = -1.5 end
    if fx_is("scatter") then lx, ly = math.random(-2, 1), math.random(-2, 1) end
    local ox, oy = math.floor(lx * 0.7 + 0.5), math.floor(ly * 0.7 + 0.5)
    screen.level(0)
    screen.rect(cx - 5 + ox, ey + 1 + oy, 2, 2)
    screen.rect(cx + 3 + ox, ey + 1 + oy, 2, 2)
    screen.fill()
  end
  -- mouth
  screen.level(1)
  if m.mouth > 0 then
    screen.rect(cx - 2, top + 11, 4, math.min(3, math.ceil(m.mouth / 2)))
    screen.fill()
  else
    line(cx - 2.5, top + 11.5, cx - 1.5, top + 12.5, cx + 1.5, top + 12.5, cx + 2.5, top + 11.5)
  end
  -- what the echo throws
  screen.aa(1)
  for _, r in ipairs(m.rings) do
    screen.level(math.max(1, math.floor(r.life * 10)))
    screen.move(cx + r.r, top + 12)
    screen.arc(cx, top + 12, r.r, -0.6, 0.6)
    screen.stroke()
  end
  screen.aa(0)
end

local function draw_fx_bar()
  local text = (message and util.time() < message_until) and message or FX[fx]
  if fx_on then
    screen.level(15)
    screen.rect(52, 57, 76, 7)
    screen.fill()
    screen.level(0)
    screen.move(54, 63)
    screen.text(text)
  elseif held[1] then
    screen.level(12)
    screen.move(54, 63)
    screen.text("< " .. text .. " >")
  else
    screen.level(4)
    screen.move(54, 63)
    screen.text(text)
  end
end

local function draw_intro()
  local t = now_s()
  screen.font_size(16)
  screen.level(15)
  screen.move(6, 34)
  screen.text("poche")
  screen.font_size(8)
  screen.level(5)
  screen.move(7, 45)
  screen.text("a drum machine")
  screen.move(7, 53)
  screen.text("for your pocket")
  mascot.arms = (math.floor(t * 4) % 2 == 0) and 6 or 0
  draw_mascot(102, 52, true)
end

function redraw()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)
  screen.line_width(1)
  if util.time() < intro_until then
    draw_intro()
    screen.update()
    return
  end
  draw_header()
  if held[1] and not fx_on then draw_patterns() else draw_steps() end
  draw_sound()
  draw_knobs()
  draw_mascot(116, 52)
  draw_fx_bar()
  -- crush is something you can see as well as hear, on the pads
  if fx_is("crush") then
    screen.level(0)
    for y = 12, 58, 3 do screen.rect(0, y, 50, 1) end
    screen.fill()
  end
  screen.update()
end

local function tick()
  for s = 1, NSOUNDS do
    if (flash[s] or 0) > 0 then flash[s] = math.max(0, flash[s] - 1.2) end
  end
  local m = mascot
  if m.squash > 0 then m.squash = math.max(0, m.squash - 0.5) end
  if m.mouth > 0 then m.mouth = m.mouth - 1 end
  if m.arms > 0 then m.arms = m.arms - 1 end
  if m.flap > 0 then m.flap = math.max(0, m.flap - 0.4) end
  if m.bob > 0 then m.bob = math.max(0, m.bob - 0.15) end
  if m.blink > 0 then
    m.blink = m.blink - 1
  elseif math.random() < 0.008 then
    m.blink = 4
  end
  for i = #m.rings, 1, -1 do
    local r = m.rings[i]
    r.r, r.life = r.r + 0.8, r.life - 0.05
    if r.life <= 0 then table.remove(m.rings, i) end
  end
  redraw()
  grid_redraw()
end

-- ---------------------------------------------------------------- params

local function add_params()
  for i, s in ipairs(musicutil.SCALES) do scale_names[i] = s.name end
  local minor_penta = 1
  for i, n in ipairs(scale_names) do
    if n == "Minor Pentatonic" then minor_penta = i end
  end

  params:add_separator("poche", "poche")
  params:add_number("swing", "swing", 0, 50, 0, function(p) return p:get() .. "%" end)
  params:add_option("scale", "scale", scale_names, minor_penta)
  params:set_action("scale", build_notes)
  params:add_number("root", "root", 24, 72, 48, function(p) return musicutil.note_num_to_name(p:get(), true) end)
  params:set_action("root", build_notes)
  params:add_trigger("copy_next", "copy pattern to next")
  params:set_action("copy_next", function()
    local to = current % NPATTERNS + 1
    patterns[to] = empty_pattern()
    for s = 1, NSOUNDS do
      for i = 1, NSTEPS do
        local st = patterns[current][s][i]
        patterns[to][s][i] = st and { a = st.a, b = st.b } or false
      end
    end
    say(string.format("copied to P%02d", to))
  end)
  params:add_trigger("clear_pattern", "clear pattern")
  params:set_action("clear_pattern", function()
    patterns[current] = empty_pattern()
    say("pattern cleared")
  end)

  params:add_separator("poche_master", "master")
  params:add_control("filter", "filter", controlspec.new(-1, 1, "lin", 0.01, 0))
  params:set_action("filter", function(v) if not fx_on then engine.filt(v) end end)
  params:add_control("crush", "crush", controlspec.new(0, 1, "lin", 0.01, 0))
  params:set_action("crush", function(v) if not fx_on then engine.crush(v) end end)
  params:add_control("drive", "drive", controlspec.new(0, 1, "lin", 0.01, 0.15))
  params:set_action("drive", function(v) engine.drive(v) end)
  local divs = {}
  for i, d in ipairs(ECHO_DIVS) do divs[i] = d[1] end
  params:add_option("echo_div", "echo time", divs, 2)
  params:set_action("echo_div", update_echo)
  params:add_control("echo_fb", "echo feedback", controlspec.new(0, 0.9, "lin", 0.01, 0.35))
  params:set_action("echo_fb", function(v) if not fx_on then engine.dfb(v) end end)
  params:add_control("echo_level", "echo level", controlspec.new(0, 1, "lin", 0.01, 0.6))
  params:set_action("echo_level", function(v) engine.dmix(v) end)
  params:add_control("room", "room", controlspec.new(0, 1, "lin", 0.01, 0.12))
  params:set_action("room", function(v) engine.verb(v) end)
  params:add_control("volume", "volume", controlspec.new(0, 1.5, "lin", 0.01, 0.8))
  params:set_action("volume", function(v) engine.level(v) end)

  for s = 1, NSOUNDS do
    local snd = SOUNDS[s]
    params:add_group("sound_" .. s, string.format("%02d %s", s, snd.name), 3)
    params:add_control("level_" .. s, "level", controlspec.new(0, 1, "lin", 0.01, snd.level))
    params:add_control("pan_" .. s, "pan", controlspec.new(-1, 1, "lin", 0.01, snd.pan))
    params:add_control("send_" .. s, "echo send", controlspec.new(0, 1, "lin", 0.01, snd.send))
  end

  params.action_write = function(filename, name, number)
    save_state(DATA .. number .. ".data")
  end
  params.action_read = function(filename, silent, number)
    load_state(DATA .. number .. ".data")
  end
  params.action_delete = function(filename, name, number)
    os.remove(DATA .. number .. ".data")
  end
end

-- ---------------------------------------------------------------- life

function init()
  started = util.time()
  intro_until = started + 1.8
  reset_knobs()
  demo()
  add_params()
  params:bang()
  build_notes()
  load_state(DATA .. "state.data")

  clock.transport.start = start
  clock.transport.stop = stop

  redraw_metro = metro.init(tick, 1 / 30)
  redraw_metro:start()
end

function cleanup()
  save_state(DATA .. "state.data")
  if seq_clock then clock.cancel(seq_clock) end
  if redraw_metro then redraw_metro:stop() end
  clock.transport.start = nil
  clock.transport.stop = nil
end
