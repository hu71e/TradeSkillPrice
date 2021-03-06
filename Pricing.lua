--[[----------------------------------------------------------------------------

    Copyright 2019-2020 Mike Battersby

    This file is part of TradeSkillPrice.

    TradeSkillPrice is free software; you can redistribute it or modify it
    under the terms of the GNU General Public License as published by the Free
    Software Foundation, version 2, 1991.

    TradeSkillPrice is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
    or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
    for more details.

    See the file LICENSE.txt for details.

----------------------------------------------------------------------------]]--

local recipeInfoCache = { }
local itemRecipesCache = { }
local itemCostCache =  { }

-- TradeSkillPrice._recipeInfoCache = recipeInfoCache
-- TradeSkillPrice._itemRecipesCache = itemRecipesCache
-- TradeSkillPrice._itemCostCache = itemCostCache

local function MultiplyTooltipInfo(tooltipInfo, n)
    for _, infoLine in ipairs(tooltipInfo) do
        infoLine[2] = infoLine[2] * n
        infoLine[3] = infoLine[3] * n
    end
    return tooltipInfo
end

local function UpdateRecipeInfoCacheObject(object)
    if object.type == 'header' or object.type == 'subheader' then
        return
    end

    if recipeInfoCache[object.recipeID] then
        recipeInfoCache[object.recipeID].craftable = object.craftable
        recipeInfoCache[object.recipeID].disabled = object.disabled
        recipeInfoCache[object.recipeID].learned = object.learned
        return
    end

    object.itemLink = C_TradeSkillUI.GetRecipeItemLink(object.recipeID)
    object.itemID = GetItemInfoFromHyperlink(object.itemLink)

    if not object.itemID then
        object.itemID = TradeSkillPrice.scrollData[object.recipeID]
        object.numCreated = 1
    else
        local a, b = C_TradeSkillUI.GetRecipeNumItemsProduced(object.recipeID)
        object.numCreated = (a+b)/2
    end

    object.reagents = object.reagents or { }

    for i=1, C_TradeSkillUI.GetRecipeNumReagents(object.recipeID) do
        local _, _, count = C_TradeSkillUI.GetRecipeReagentInfo(object.recipeID, i)
        local reagentItemLink = C_TradeSkillUI.GetRecipeReagentItemLink(object.recipeID, i)
        local reagentItemID = GetItemInfoFromHyperlink(reagentItemLink)

        if reagentItemID then
            object.reagents[reagentItemID] = count
            TradeSkillPrice.db.knownReagents[reagentItemID] = true
        end
    end

    recipeInfoCache[object.recipeID] = object

    if object.itemID then
        itemRecipesCache[object.itemID] = itemRecipesCache[object.itemID] or { }
        table.insert(itemRecipesCache[object.itemID], object.recipeID)
    end
end

function TradeSkillPrice:ClearItemCostCache()
    table.wipe(itemCostCache)
end

function TradeSkillPrice:UpdateRecipeInfoCache()
    if C_TradeSkillUI.IsTradeSkillLinked() then
        return
    end

    for i, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
        local object = C_TradeSkillUI.GetRecipeInfo(recipeID)
        UpdateRecipeInfoCacheObject(object)
    end
end

local function GetMinItemBuyCost(itemID, count)
    local minCost, minCostSource

    for _,f in ipairs(TradeSkillPrice.costFunctions) do
        local c, s = f.func(itemID, count)
        if c and (minCost == nil or c < minCost) then
            minCost, minCostSource = c, s
        end
    end

    return minCost, minCostSource
end

local GetItemCostRecursive, GetRecipeCostRecursive

GetRecipeCostRecursive = function (recipeID, count, seen)
    -- Can't depend on ourself, definitely not a winning strategy
    if seen[recipeID] ~= nil then
        return
    end

    local object = recipeInfoCache[recipeID]

    -- Abort if we don't know it
    if not object.learned then
        return
    end

    -- Abort if we know a better rank
    if object.nextRecipeID and recipeInfoCache[object.nextRecipeID].learned then
        return
    end

    seen[recipeID] = true

    count = count / object.numCreated

    local cost, source
    local ttInfo = { { object.name, count } }

    for itemID, numRequired in pairs(object.reagents) do
        local c, s, t = GetItemCostRecursive(itemID, numRequired * count, seen)
        if c ~= nil then
            cost = (cost or 0) + c
            for _,v in ipairs(t) do table.insert(ttInfo, v) end
        elseif select(14, GetItemInfo(itemID)) ~= 1 then
            -- We found an unbound object we don't have a price for
            -- What if GetItemInfo doesn't work yet?
            return
        end
    end
    if cost then
        return cost, "r", ttInfo
    end
end

GetItemCostRecursive = function (itemID, count, seen)
    local minCost, minCostSource = GetMinItemBuyCost(itemID, count)
    local ttInfo

    for _,recipeID in ipairs(itemRecipesCache[itemID] or {}) do
        local c, s, t = GetRecipeCostRecursive(recipeID, count, CopyTable(seen))
        if c and (minCost == nil or c < minCost) then
            minCost, minCostSource, ttInfo = c, s, t
        end
    end

    if minCost then
        if not ttInfo then
            local _, itemLink = GetItemInfo(itemID)
            ttInfo = { { itemLink, count, minCost } }
        end
        return minCost, minCostSource, ttInfo
    end
end

function TradeSkillPrice:GetRecipeItem(recipeID)
    local itemLink = C_TradeSkillUI.GetRecipeItemLink(recipeID)
    local itemID = GetItemInfoFromHyperlink(itemLink)
                    or TradeSkillPrice.scrollData[recipeID]
    return itemID
end

function TradeSkillPrice:GetItemCost(itemID)
    return GetItemCostRecursive(itemID, 1, {})
end

function TradeSkillPrice:GetRecipeCost(recipeID)
    return GetRecipeCostRecursive(recipeID, 1, {})
end

function TradeSkillPrice:GetItemValue(itemID)
    local value, source

    for _,f in ipairs(TradeSkillPrice.valueFunctions) do
        local v, s = f.func(itemID, 1)
        if v and v > (value or 0) then
            value, source = v, s
        end
    end

    return value, source
end

function TradeSkillPrice:GetRecipeValue(recipeID)
    local item = self:GetRecipeItem(recipeID)
    if item then
        return self:GetItemValue(item)
    end
end
