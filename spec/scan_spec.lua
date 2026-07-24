local bmi = require("spec.bmi")

-- scan.lua's one-time store migration (#31). Accounts that scanned before the skill-line-index
-- bucketing fix (#13) have class-base spells leaked into db.spellTermsByRace, and a default scan
-- is additive, so those entries survive forever unless something wipes them. The migration wipes
-- byRace + byClass once, gated on a schema marker scan.lua owns outright; the shipped baseline
-- (data/spellterms.lua) backfills the search index so nothing becomes unfindable in the meantime.

-- The shipped baseline, read once from a throwaway namespace. Each load builds its own copy of
-- the table, so using it to seed a live store never aliases the namespace under test.
local BUNDLE = bmi.session().ns.bundledSpellTerms

-- The marker value scan.lua currently writes. Discovered rather than hard-coded so an
-- intentional bump doesn't fail the suite — the specs assert on behaviour, not on the number.
-- It is asserted to be a number up front: were the marker write ever dropped, MARKER would be
-- nil and every `assert.are.equal(MARKER, ...)` below would silently become nil == nil.
local MARKER = (function()
    local h = bmi.session()
    h.login()
    return h.db.spellTermsSchema
end)()

describe("scan.lua schema marker", function()
    it("is written as a number, so the marker assertions below can fail", function()
        assert.is_number(MARKER)
    end)
end)

-- A leaked class-base spell of the kind pre-#13 scans wrote into byRace: a Death Knight's Death
-- Strike recorded under Blood Elf. The fileID is synthetic so it can never collide with the
-- bundle, which makes it a reliable "this is pollution" marker in the /bmi diff specs.
local LEAK_ICON, LEAK_NAME = 4242424, " death strike "
local BLOOD_ELF, DEATH_KNIGHT, BLOOD_SPEC = 10, 6, 250

-- The smallest key of a bucket set, so samples are deterministic across runs.
local function firstKey(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys)
    return keys[1]
end

-- A real (bucketKey, fileID, blob) triple out of the shipped baseline.
local function sampleFrom(buckets)
    local key = firstKey(buckets)
    local fileID = firstKey(buckets[key])
    return key, fileID, buckets[key][fileID]
end

-- rebuildMerged splits stored blobs on whitespace, so the merged index holds words, not whole
-- names. A blob is "still searchable" when every one of its words is in the merged entry.
local function assertSearchable(ns, fileID, blob)
    local terms = ns.SpellTermsFor(fileID)
    for word in blob:gmatch("%S+") do
        assert.is_truthy(terms:find(" " .. word .. " ", 1, true),
            ("%q missing from the merged terms for icon %d (%q)"):format(word, fileID, terms))
    end
end

-- A SavedVariables table as a pre-#13 account left it: correct spec terms, a racial, and a
-- class-base spell leaked into the race bucket. No schema marker — that key did not exist yet.
local function pollutedDB()
    return {
        spellTermsBySpec = { [BLOOD_SPEC] = { [3001] = " marrowrend " } },
        spellTermsByRace = { [BLOOD_ELF] = { [1001] = " arcane torrent ", [LEAK_ICON] = LEAK_NAME } },
        spellTermsByClass = {},
    }
end

describe("scan.lua store migration", function()
    it("wipes the race and class stores on the first login after the fix", function()
        local h = bmi.session({ db = pollutedDB() })
        h.login()
        assert.are.same({}, h.db.spellTermsByRace)
        assert.are.same({}, h.db.spellTermsByClass)
    end)

    it("keeps the spec store, which was never mis-bucketed", function()
        local h = bmi.session({ db = pollutedDB() })
        h.login()
        assert.are.same({ [BLOOD_SPEC] = { [3001] = " marrowrend " } }, h.db.spellTermsBySpec)
    end)

    it("records the schema marker so the wipe is one-time", function()
        local h = bmi.session({ db = pollutedDB() })
        assert.is_nil(h.db.spellTermsSchema)
        h.login()
        assert.are.equal(MARKER, h.db.spellTermsSchema)
    end)

    it("leaves a later session's freshly scanned terms alone", function()
        local db = pollutedDB()
        bmi.session({ db = db }).login()

        -- Post-migration scans refill the buckets; the next login must not throw them away.
        db.spellTermsByRace = { [BLOOD_ELF] = { [1001] = " arcane torrent " } }
        db.spellTermsByClass = { [DEATH_KNIGHT] = { [2001] = " death strike " } }

        local next_ = bmi.session({ db = db })
        next_.login()
        assert.are.same({ [BLOOD_ELF] = { [1001] = " arcane torrent " } }, next_.db.spellTermsByRace)
        assert.are.same({ [DEATH_KNIGHT] = { [2001] = " death strike " } }, next_.db.spellTermsByClass)
        assert.are.equal(MARKER, next_.db.spellTermsSchema)
    end)

    it("is a harmless no-op on a fresh install", function()
        local h = bmi.session({ db = {} })
        h.login()
        assert.are.same({}, h.db.spellTermsBySpec)
        assert.are.same({}, h.db.spellTermsByRace)
        assert.are.same({}, h.db.spellTermsByClass)
        assert.are.equal(MARKER, h.db.spellTermsSchema)
    end)

    it("re-wipes when the marker is stale, not merely absent", function()
        local db = pollutedDB()
        db.spellTermsSchema = MARKER - 1  -- as a future schema bump would leave it
        local h = bmi.session({ db = db })
        h.login()
        assert.are.same({}, h.db.spellTermsByRace)
        assert.are.equal(MARKER, h.db.spellTermsSchema)
    end)

    it("keeps the schema marker private to scan.lua", function()
        -- The marker lives on ns.db like the three bucket tables, so it must be referenced from
        -- scan.lua alone: deleting the module then leaves no dangling read anywhere else.
        local toc = assert(io.open("BetterMacroIcons.toc", "r"))
        local manifest = toc:read("*a")
        toc:close()

        local checked = 0
        for path in manifest:gmatch("[^\r\n]+") do
            if path:find("%.lua$") and path ~= "scan.lua" then
                local f = assert(io.open(path, "r"), "listed in the toc but missing: " .. path)
                local src = f:read("*a")
                f:close()
                checked = checked + 1
                assert.is_nil(src:find("spellTermsSchema", 1, true),
                    path .. " references the scan.lua-owned schema marker")
            end
        end
        assert.is_true(checked > 0, "no sibling lua files found in the toc")
    end)
end)

describe("scan.lua migration search coverage", function()
    it("still finds a racial whose only live copy the migration destroyed", function()
        local raceID, fileID, blob = sampleFrom(BUNDLE.byRace)
        local db = pollutedDB()
        db.spellTermsByRace[raceID] = { [fileID] = blob }  -- the live scan's own copy

        local h = bmi.session({ db = db })
        h.login()

        assert.are.same({}, h.db.spellTermsByRace)         -- destroyed in SavedVariables...
        assertSearchable(h.ns, fileID, blob)               -- ...but still searchable, from the bundle
    end)

    it("still finds a class-base spell after the wipe", function()
        local classID, fileID, blob = sampleFrom(BUNDLE.byClass)
        local db = pollutedDB()
        db.spellTermsByClass[classID] = { [fileID] = blob }

        local h = bmi.session({ db = db })
        h.login()

        assert.are.same({}, h.db.spellTermsByClass)
        assertSearchable(h.ns, fileID, blob)
    end)

    it("serves every term in the shipped baseline once the stores are empty", function()
        local h = bmi.session({ db = pollutedDB() })
        h.login()
        for _, buckets in ipairs({ BUNDLE.bySpec, BUNDLE.byRace, BUNDLE.byClass }) do
            for _, section in pairs(buckets) do
                for fileID, blob in pairs(section) do
                    assertSearchable(h.ns, fileID, blob)
                end
            end
        end
    end)

    it("drops only the leaked term, which the baseline never had", function()
        local h = bmi.session({ db = pollutedDB() })
        h.login()
        assert.are.equal("", h.ns.SpellTermsFor(LEAK_ICON))
    end)
end)

describe("scan.lua migration effect on /bmi diff", function()
    -- The maintainer's client after #29/#30: bySpec matches the baseline it was exported from,
    -- while byRace still carries pre-#13 leakage. Acceptance criterion 4 is that /bmi diff reads
    -- 0 there with no post-migration scans, instead of needing a hand-run /bmi reset.
    -- Sections are copied, not aliased: BUNDLE is shared by every spec in this file, and a live
    -- store is writable (a /bmi scan addName()s straight into it), so handing out the baseline's
    -- own tables would let one test corrupt the fixture for the rest.
    local function maintainerDB()
        local db = pollutedDB()
        db.spellTermsBySpec = {}
        for specID, section in pairs(BUNDLE.bySpec) do
            local copy = {}
            for fileID, blob in pairs(section) do copy[fileID] = blob end
            db.spellTermsBySpec[specID] = copy
        end
        return db
    end

    it("reports nothing new once the migration has run", function()
        local h = bmi.session({ db = maintainerDB() })
        h.login()
        h.run("diff")

        local report = h.lastReport()
        assert.are.equal("BMI Diff", report.title)
        assert.are.equal(1, #report.lines)
        assert.is_truthy(report.lines[1]:find("matches the bundled baseline", 1, true))
    end)

    it("would still report the leaked spell if the migration were skipped", function()
        -- Same data, marker already current, so migrateStores does nothing — the state this
        -- change exists to fix. Guards the spec above against passing for the wrong reason.
        local db = maintainerDB()
        db.spellTermsSchema = MARKER

        local h = bmi.session({ db = db })
        h.login()
        h.run("diff")

        local report = h.lastReport()
        assert.is_truthy(report.lines[1]:find("beyond the bundled baseline", 1, true))
        local leaked = table.concat(report.lines, "\n")
        assert.is_truthy(leaked:find(tostring(LEAK_ICON), 1, true))
    end)
end)

describe("scan.lua rebuilds cleanly after the migration", function()
    it("routes racials, class-base spells and spec spells to their own buckets", function()
        local h = bmi.session({
            db = pollutedDB(),
            race = BLOOD_ELF,
            class = DEATH_KNIGHT,
            spellbook = {
                { spells = { { 1001, "Arcane Torrent" } } },                    -- 1: General → byRace
                { spells = { { 2001, "Death Strike" } } },                      -- 2: Class   → byClass
                { specID = BLOOD_SPEC, spells = { { 3001, "Marrowrend" } } },   -- spec line  → bySpec
            },
        })
        h.login()
        h.run("scan")

        assert.are.same({ [BLOOD_ELF] = { [1001] = " arcane torrent " } }, h.db.spellTermsByRace)
        assert.are.same({ [DEATH_KNIGHT] = { [2001] = " death strike " } }, h.db.spellTermsByClass)
        assert.are.equal(" marrowrend ", h.db.spellTermsBySpec[BLOOD_SPEC][3001])
    end)

    it("keeps /bmi reset and the migration wiping the same buckets", function()
        local h = bmi.session({ db = pollutedDB() })
        h.login()
        h.db.spellTermsByRace = { [BLOOD_ELF] = { [1001] = " arcane torrent " } }
        h.db.spellTermsByClass = { [DEATH_KNIGHT] = { [2001] = " death strike " } }

        h.run("reset")

        assert.are.same({}, h.db.spellTermsByRace)
        assert.are.same({}, h.db.spellTermsByClass)
        assert.are.same({ [BLOOD_SPEC] = { [3001] = " marrowrend " } }, h.db.spellTermsBySpec)
    end)
end)
