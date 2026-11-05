--!nonstrict
-- Direct plugin translations.
--
-- The shell loads a plugin's translation catalog before it applies a live
-- language change (the plugin reload runs first, the i18n service updates
-- after), so `noctalia.tr()` can still be one language behind. Reading the
-- effective `shell.lang` and the JSON files ourselves keeps every entry in
-- sync as soon as the entry reloads.

local RTL_LANGUAGES = {
  ar = true,
  ckb = true,
  dv = true,
  fa = true,
  he = true,
  ps = true,
  sd = true,
  ug = true,
  ur = true,
  yi = true,
}

local function normalize(value)
  if type(value) ~= "string" or value == "" then
    return nil
  end
  return value:lower():gsub("_", "-"):match("^([a-z]+)")
end

local function flatten(node, prefix, out)
  for key, value in pairs(node) do
    local path = prefix == "" and key or (prefix .. "." .. key)
    if type(value) == "table" then
      flatten(value, path, out)
    elseif type(value) == "string" then
      out[path] = value
    end
  end
end

local function readCatalog(dir, lang)
  local path = dir .. "/translations/" .. lang .. ".json"
  if not noctalia.fileExists(path) then
    return nil
  end
  local raw = noctalia.readFile(path)
  if type(raw) ~= "string" or raw == "" then
    return nil
  end
  local ok, decoded = pcall(noctalia.json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  local values = {}
  flatten(decoded, "", values)
  return values
end

local function shellLanguage()
  if type(noctalia.getSetting) ~= "function" then
    return nil
  end
  -- Read the whole `[shell]` table rather than `shell.lang`: the key is often
  -- absent (the shell defaults to en-US), which would log a warning, and
  -- reloading when any shell setting changes is what the bar wants anyway.
  local shell = noctalia.getSetting("shell")
  if type(shell) ~= "table" then
    return nil
  end
  return normalize(shell.lang)
end

local lang = nil
local values = {}

local function loadCatalog(language)
  lang = language
  values = {}
  if type(noctalia.pluginDir) ~= "function" then
    return
  end
  local dir = noctalia.pluginDir()
  if type(dir) ~= "string" or dir == "" then
    return
  end
  values = readCatalog(dir, "en") or {}
  if language ~= "en" then
    local localized = readCatalog(dir, language)
    if localized ~= nil then
      for key, value in pairs(localized) do
        values[key] = value
      end
    end
  end
end

local M = {}

-- Re-read the effective language. Call once per render/update: a language
-- change can land after the entry was reloaded, and the next tick then picks
-- it up without waiting for another reload.
function M.refresh()
  local nextLang = shellLanguage() or "en"
  if nextLang ~= lang then
    loadCatalog(nextLang)
  end
  return lang
end

function M.lang()
  return lang
end

function M.isRtl()
  return RTL_LANGUAGES[lang] == true
end

-- Hijri dates have their own language preference: `auto` follows the shell,
-- `arabic` keeps the Hijri date in Arabic even in an English shell, and
-- `english` does the reverse.
function M.hijriLang()
  local preference = nil
  if type(noctalia.getConfig) == "function" then
    preference = noctalia.getConfig("hijri_language")
  end
  if preference == "arabic" then
    return "ar"
  end
  if preference == "english" then
    return "en"
  end
  return RTL_LANGUAGES[lang] == true and "ar" or "en"
end

function M.hijriIsArabic()
  return M.hijriLang() == "ar"
end

function M.tr(key, fallback)
  local value = values[key]
  if type(value) == "string" and value ~= "" then
    return value
  end
  -- Direct file loading failed (or the module was loaded outside the normal
  -- plugin directory): fall back to the shell catalog.
  local text = noctalia.tr(key)
  if type(text) == "string" and text ~= "" and text ~= key then
    return text
  end
  return fallback or key
end

M.refresh()

return M
