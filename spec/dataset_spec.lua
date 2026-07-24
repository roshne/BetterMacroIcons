local bmi = require("spec.bmi")

-- Two Retribution Paladin spells that share BOTH an icon (fileID 461860) and the word "verdict" —
-- taken verbatim from data/spellterms.lua. This is the shape that the old word-splitting
-- export/diff corrupted: re-adding "verdict" hit the space-bounded dedup, so the second name
-- collapsed from "templar's verdict" to "templar's". scan.lua stores whole names, so the tooling
-- has to carry them through whole as well.
local SHARED = " final verdict templar's verdict "
local RET, ICON = 70, 461860

describe("/bmi export", function()
    it("keeps a shared-icon blob whose two names share a word", function()
        local h = bmi.load({ bySpec = { [RET] = { [ICON] = SHARED } } })
        assert.are.equal(SHARED, bmi.parse(h.export()).bySpec[RET][ICON])
    end)

    it("is round-trip stable: re-exporting its own output reproduces it", function()
        local live = {
            bySpec = { [RET] = { [ICON] = SHARED, [135875] = " avenging wrath " } },
            byRace = { [91] = { [999] = " arcane pulse " } },
            byClass = { [2] = { [123] = " some class spell shared thing " } },
        }
        local first = bmi.load(live).export()
        local second = bmi.load(live, bmi.parse(first)).export()
        assert.are.equal(table.concat(first, "\n"), table.concat(second, "\n"))
        assert.are.equal(SHARED, bmi.parse(second).bySpec[RET][ICON])
    end)

    it("folds a faction race variant onto its canonical id", function()
        local h = bmi.load({ byRace = { [91] = { [999] = " arcane pulse " } } })
        local out = bmi.parse(h.export())
        assert.are.equal(" arcane pulse ", out.byRace[86][999])
        assert.is_nil(out.byRace[91])
    end)

    it("keeps the superset when a live scan extends a bundled blob", function()
        local extended = " final verdict templar's verdict wake of ashes "
        local h = bmi.load({ bySpec = { [RET] = { [ICON] = extended } } },
                           { bySpec = { [RET] = { [ICON] = SHARED } } })
        assert.are.equal(extended, bmi.parse(h.export()).bySpec[RET][ICON])
    end)
end)

describe("/bmi diff", function()
    -- The report line for one icon, e.g. "  spec70 [461860]: wake of ashes" (nil if not reported).
    local function lineFor(lines, fileID)
        for _, line in ipairs(lines) do
            if line:find("[" .. fileID .. "]", 1, true) then return line end
        end
    end

    it("reports nothing when the live store matches the bundle", function()
        local same = { bySpec = { [RET] = { [ICON] = SHARED } } }
        local lines = bmi.load(same, { bySpec = same.bySpec }).diff()
        assert.are.equal(1, #lines)
        assert.is_truthy(lines[1]:find("matches the bundled baseline", 1, true))
    end)

    it("reports a newly discovered icon as one whole name", function()
        local live = { bySpec = { [RET] = { [ICON] = SHARED, [1109508] = " templar strike " } } }
        local lines = bmi.load(live, { bySpec = { [RET] = { [ICON] = SHARED } } }).diff()
        assert.are.equal("  spec70 [1109508]: templar strike", lineFor(lines, 1109508))
        assert.is_nil(lineFor(lines, ICON))  -- the unchanged blob is not a new discovery
    end)

    it("reports a multi-name blob whole, not word by word", function()
        local live = { bySpec = { [65] = { [461859] = " light of dawn holy radiance " } } }
        local lines = bmi.load(live, {}).diff()
        assert.are.equal("  spec65 [461859]: light of dawn holy radiance", lineFor(lines, 461859))
    end)

    it("reports only the added run when a live blob extends a bundled one", function()
        local live = { bySpec = { [RET] = { [ICON] = SHARED .. "wake of ashes " } } }
        local lines = bmi.load(live, { bySpec = { [RET] = { [ICON] = SHARED } } }).diff()
        assert.are.equal("  spec70 [461860]: wake of ashes", lineFor(lines, ICON))
    end)

    it("reports a whole name that shares a word with a different bundled name", function()
        local live = { bySpec = { [RET] = { [ICON] = " templar's verdict " } } }
        local lines = bmi.load(live, { bySpec = { [RET] = { [ICON] = " final verdict " } } }).diff()
        assert.are.equal("  spec70 [461860]: templar's verdict", lineFor(lines, ICON))
    end)
end)
