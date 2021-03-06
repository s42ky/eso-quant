-- This file is part of Quant
--
-- (C) 2015 Scott Yeskie (Sasky)
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.

Quant.skpwr = {}
local skpwr = Quant.skpwr
local skill = Quant.skill
local stat = Quant.stat

function skpwr:statSkill(progIndex,morph,level)
    local id = GetAbilityProgressionAbilityId(progIndex, morph, level)

    --Get main skill key
    local name = GetAbilityName(id)
    local key = name .. "-" .. level
    if self.data[key] == nil then self.data[key] = {} end

    --Get entry point key
    local power = stat:getKey(id)

    --Iterate through the description extracting numbers
    local desc = GetAbilityDescription(id)
    local i = 1
    for num in string.gfind(desc, "|c......([0-9.]+)|r") do
        if self.data[key][i] == nil then self.data[key][i] = {} end
        self.data[key][i][power] = tostring(num)
        i = i + 1
    end
end

function skpwr:recordIteration()
    skill:iterateSkills(
        function(skillType, skillLineIndex, abilityIndex)
            local _,_,_,passive,_,_,progIndex = GetSkillAbilityInfo(skillType, skillLineIndex, abilityIndex)
            if not passive then
                self:statSkill(progIndex,0,4)
                self:statSkill(progIndex,1,4)
                self:statSkill(progIndex,2,4)
            end
        end,
        self.filter
    )
end

local iterationQueue = {}
function skpwr:iterationExecuter()
    local i = iterationQueue.i or 1
    local item = iterationQueue[i]
    --+1 so we get a no-op at the end
    if i == (#iterationQueue + 1) then
        --Make sure last gear stats recorded and finish
        self:recordIteration()
        EVENT_MANAGER:UnregisterForUpdate("QuantSkillCurve")
        self:finishScan()
    elseif(item.reset) then
        if(iterationQueue.resetting == 0) then
            d("Resetting for next gear set...")
            WYK_Outfitter.GC.StripNaked()
            iterationQueue.resetting = 1
        elseif(iterationQueue.resetting >= 5) then
            d("Reset finished")
            iterationQueue.i = i + 1
            iterationQueue.resetting = 0
        else
            iterationQueue.resetting = iterationQueue.resetting + 1
        end
    else
        local bag,pos = WYK_Outfitter.GC.FindItem(item.id)
        EquipItem(bag,pos,item.eslot)
        self:recordIteration()
        --Output progress
        if (i % self.progressCheck) == 0 then
            d("Processing... " .. iterationQueue.i .. "/" .. (#iterationQueue))
        end
        --Increment
        iterationQueue.i = i+1
    end
end

function skpwr:prepScan()
    iterationQueue = {}
    --Record equipped gear
    self.gear = WYK_Outfitter.GC.ParseGear()
    --remove weapons from gear set
    self.gear[EQUIP_SLOT_MAIN_HAND] = nil
    self.gear[EQUIP_SLOT_OFF_HAND] = nil
    self.gear[EQUIP_SLOT_BACKUP_MAIN] = nil
    self.gear[EQUIP_SLOT_BACKUP_OFF] = nil

    --Use Wykkyd to unequip gear
    d("Waiting 5 seconds for Wykkyd's Outfitter...")
    WYK_Outfitter.GC.StripNaked()
    zo_callLater(function() self:initScan() end, 5000)
end

--NOTE: Enter into prepScan NOT initScan
function skpwr:initScan()
    --Iterate bags to find weapons (bows)
    self.weapons = {}
    self.gearSets = {
        ["Maximum Magicka Enchantment"] = {},
        ["Maximum Stamina Enchantment"] = {},
        ["Maximum Health Enchantment"] = {},
    }

    --Scan backpack for items to equip
    local slots = GetBagSize(BAG_BACKPACK)
    for slot = 0, slots, 1 do
        local uid = GetItemUniqueId( BAG_BACKPACK, slot )
        if uid ~= nil then
            local type = GetItemType(BAG_BACKPACK, slot)
            if(type == ITEMTYPE_WEAPON) then
            if(GetItemWeaponType(BAG_BACKPACK, slot) == WEAPONTYPE_BOW) then
                table.insert(self.weapons, uid)
            end
            elseif(type == ITEMTYPE_ARMOR) then
                local link = GetItemLink(BAG_BACKPACK, slot)
                local ench, eType = GetItemLinkEnchantInfo(link)
                if(ench and self.gearSets[eType]) then
                    table.insert(self.gearSets[eType], {
                        eslot=GetComparisonEquipSlotsFromItemLink(link),
                        id=uid
                    })
                end
            end
        end
    end

    --Build iteration queue
    skpwr:addWeaponIterations()
    for _,set in pairs(self.gearSets) do
        for _,item in pairs(set) do
            table.insert(iterationQueue, item)
            skpwr:addWeaponIterations()
        end
        table.insert(iterationQueue, {reset=true})
    end

    --Prep iterator variables
    self.progressCheck = #self.weapons +1
    iterationQueue.i = 1
    iterationQueue.resetting = 0

    --Doesn't really go faster than 1s anyways. Let the game not choke as much
    EVENT_MANAGER:RegisterForUpdate("QuantSkillCurve", 1000, function()
        self:iterationExecuter()
    end)
end

function skpwr:finishScan()
    d("Finished scan. /reloadui to save out or inspect with /zgoo Quant.skpwr.data")
    self.itq = iterationQueue
end

function skpwr:addWeaponIterations()
    for _,v in pairs(self.weapons) do
        table.insert(iterationQueue, {eslot=EQUIP_SLOT_MAIN_HAND, id=v})
    end
end

Quant:registerCmd("itr-all-skills", "|cFF0000WARNING. See README for instructions", function()
    d("Beginning skill iteration. This may take awhile.")
    skpwr.filter = {
        SKILL_TYPE_TRADESKILL = 0,
    }
    if not skpwr.data then
        skpwr.data = Quant:load("SkillsCurve")
    end
    skpwr:prepScan()
end)

Quant:registerCmd("itr-class-skills", "|cFF0000WARNING. See README for instructions", function()
    d("Beginning class skill iteration. This may take awhile.")
    skpwr.filter = {
        SKILL_TYPE_TRADESKILL = 0,
        SKILL_TYPE_ARMOR = 0,
        SKILL_TYPE_AVA = 0,
        SKILL_TYPE_GUILD = 0,
        SKILL_TYPE_RACIAL = 0,
        SKILL_TYPE_WEAPON = 0,
        SKILL_TYPE_WORLD = 0,
    }
    if not skpwr.data then
        skpwr.data = Quant:load("SkillsCurve")
    end
    skpwr:prepScan()
end)

--Try to execute all skills
Quant:registerCmd("skills", "|cFF0000WARNING. See README for instructions", function()
    Quant:cli('itr-class-skills')
    Quant:cli('skill-full') --Just do these on naked char for standard
end)