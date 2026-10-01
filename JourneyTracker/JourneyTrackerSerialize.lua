-- JourneyTracker export encoding:
--   summary table -> JSON -> raw deflate (LibDeflate) -> base64 -> "JT1:..."
-- Pure Lua with no game API calls, so this exact file can be run outside the
-- game to check it. tools/import/decode.js reverses it with Node's Buffer
-- and zlib (inflateRawSync), no ports needed.

local ADDON_NAME, ns = ...
local Serialize = {}
ns.Serialize = Serialize

Serialize.PREFIX = "JT1:" -- format version 1
Serialize.MAP_CAP = 200   -- name-keyed maps keep their 200 biggest entries

---------------------------------------------------------------------------
-- Tables
---------------------------------------------------------------------------

function Serialize.Copy(t)
    local c = {}
    for k, v in pairs(t) do
        c[k] = type(v) == "table" and Serialize.Copy(v) or v
    end
    return c
end

-- The `limit` biggest entries of a { name = number } map (a new table).
function Serialize.Capped(map, limit)
    if type(map) ~= "table" then return map end
    local list = {}
    for k, v in pairs(map) do list[#list + 1] = { k, v } end
    if #list <= limit then return map end
    table.sort(list, function(a, b) return (tonumber(a[2]) or 0) > (tonumber(b[2]) or 0) end)
    local out = {}
    for i = 1, limit do out[list[i][1]] = list[i][2] end
    return out
end

---------------------------------------------------------------------------
-- JSON encoder
--
-- A table whose keys are exactly 1..n becomes an array (an empty table too,
-- so lists and maps both read safely in JavaScript); anything else becomes
-- an object, with number keys written as strings ("20"). Object keys are
-- sorted so the same data always gives the same text.
---------------------------------------------------------------------------

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
                  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function EncodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function EncodeNumber(n)
    if n ~= n or n == math.huge or n == -math.huge then return "null" end
    if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%.0f", n) end
    return string.format("%.14g", n)
end

-- n if the table's keys are exactly 1..n, else nil.
local function ArrayLength(t)
    local count = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return nil end
        count = count + 1
    end
    for i = 1, count do
        if t[i] == nil then return nil end
    end
    return count
end

local Encode

local function EncodeTable(t, out, depth)
    if depth > 50 then error("table nested too deeply to export") end
    local n = ArrayLength(t)
    if n then
        out[#out + 1] = "["
        for i = 1, n do
            if i > 1 then out[#out + 1] = "," end
            Encode(t[i], out, depth + 1)
        end
        out[#out + 1] = "]"
        return
    end
    local pairsList = {}
    for k, v in pairs(t) do
        local key = type(k) == "string" and k or (type(k) == "number" and EncodeNumber(k)) or nil
        if key then pairsList[#pairsList + 1] = { key, v } end
    end
    table.sort(pairsList, function(a, b) return a[1] < b[1] end)
    out[#out + 1] = "{"
    for i, kv in ipairs(pairsList) do
        if i > 1 then out[#out + 1] = "," end
        out[#out + 1] = EncodeString(kv[1])
        out[#out + 1] = ":"
        Encode(kv[2], out, depth + 1)
    end
    out[#out + 1] = "}"
end

Encode = function(value, out, depth)
    local kind = type(value)
    if kind == "table" then
        EncodeTable(value, out, depth)
    elseif kind == "string" then
        out[#out + 1] = EncodeString(value)
    elseif kind == "number" then
        out[#out + 1] = EncodeNumber(value)
    elseif kind == "boolean" then
        out[#out + 1] = value and "true" or "false"
    else
        out[#out + 1] = "null"
    end
end

function Serialize.ToJSON(value)
    local out = {}
    Encode(value, out, 0)
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Base64 (standard alphabet with "=" padding, as Node's Buffer expects)
---------------------------------------------------------------------------

local B64 = {}
do
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for i = 1, 64 do B64[i - 1] = alphabet:sub(i, i) end
end

function Serialize.Base64(bytes)
    local out = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        out[#out + 1] = B64[math.floor(n / 262144) % 64] .. B64[math.floor(n / 4096) % 64]
            .. (b and B64[math.floor(n / 64) % 64] or "=") .. (c and B64[n % 64] or "=")
    end
    return table.concat(out)
end

---------------------------------------------------------------------------
-- Export string
---------------------------------------------------------------------------

-- "JT1:" export string for a summary table, plus the JSON it was made from.
function Serialize.Encode(summary)
    local deflate = ns.LibDeflate or (LibStub and LibStub("LibDeflate", true))
    if not deflate then return nil, "LibDeflate is missing from the addon's Libs folder" end
    local json = Serialize.ToJSON(summary)
    return Serialize.PREFIX .. Serialize.Base64(deflate:CompressDeflate(json)), json
end

-- Sections of a summary by JSON size, biggest first: { { "stats.deaths", bytes }, ... }.
function Serialize.SectionSizes(summary)
    local sizes = {}
    for key, value in pairs(summary) do
        if type(value) == "table" and (key == "stats" or key == "class" or key == "wrapped") then
            for sub, part in pairs(value) do
                sizes[#sizes + 1] = { key .. "." .. tostring(sub), #Serialize.ToJSON(part) }
            end
        else
            sizes[#sizes + 1] = { tostring(key), #Serialize.ToJSON(value) }
        end
    end
    table.sort(sizes, function(a, b) return a[2] > b[2] end)
    return sizes
end

---------------------------------------------------------------------------
-- Test export (/journey testexport): fixed fake data covering every kind of
-- value a real export uses. tools/import/fixtures/testexport.expected.json
-- is what it must decode to.
---------------------------------------------------------------------------

function Serialize.TestSummary()
    return {
        format = 1,
        characterId = "1b4e28ba-2fa1-4d3b-a3f5-ef19b5a7633b",
        addonVersion = "test",
        schemaVersion = 1,
        exportedAt = 1790000000,
        character = { class = "DRUID", race = "NightElf", faction = "Alliance", level = 20,
                      played = 217453, ruleset = "PvP" },
        levels = {
            snapshots = { [10] = { t = 1789000000, zone = "Elwynn Forest", gold = 1234, grouped = false } },
            stats = { [10] = { xp = 4380, kills = 52, played = 3600.5 } },
        },
        stats = {
            text = 'Quote " backslash \\ slash / newline \n tab \t carriage \r done',
            unicode = "Café, naïve, Æthelred, 日本",
            control = "bell\7end",
            itemLink = "|cff0070dd|Hitem:2672::::::::20:::::::::|h[Stringy Wolf Meat]|h|r",
            integer = 42, zero = 0, big = 1790000000, half = 47.5, tenth = 0.1,
            yes = true, no = false,
            empty = {},
            list = { 1, 2, 3 },
            listOfObjects = { { name = "Timber Wolf", count = 12 }, { name = "Kobold Vermin", count = 3 } },
            sparse = { [5] = "five", [20] = "twenty" },
            nested = { a = { b = { c = "deep" } } },
            mixedKeys = { [1] = "slot one", late = true },
            kills = { maxLevelDiff = { diff = -3, name = "Young Wolf", mobLevel = 2, level = 5 } },
        },
        class = { DRUID = { casts = { ["Healing Touch"] = 12, Wrath = 30 } } },
        wrapped = { ["W-009"] = { Camp = 120 } },
    }
end
