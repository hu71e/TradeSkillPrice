--[[----------------------------------------------------------------------------

    Copyright 2019 Mike Battersby

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

TSP._recipeInfoCache = recipeInfoCache
TSP._itemRecipesCache = itemRecipesCache
TSP._itemCostCache = itemCostCache

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

    local itemLink = C_TradeSkillUI.GetRecipeItemLink(object.recipeID)
    local itemID = GetItemInfoFromHyperlink(itemLink)

    object.itemLink = itemLink
    object.itemID = itemID

    local min, max
    if not itemID then
        itemID = TSP.scrollData[object.recipeID]
        object.numCreated = 1
    else
        local min, max = C_TradeSkillUI.GetRecipeNumItemsProduced(object.recipeID)
        object.numCreated = (min+max)/2
    end

    object.reagents = object.reagents or { }

    for i=1, C_TradeSkillUI.GetRecipeNumReagents(object.recipeID) do
        local _, _, count = C_TradeSkillUI.GetRecipeReagentInfo(object.recipeID, i)
        local reagentItemLink = C_TradeSkillUI.GetRecipeReagentItemLink(object.recipeID, i)
        local reagentItemID = GetItemInfoFromHyperlink(reagentItemLink)

        if reagentItemID then
            object.reagents[reagentItemID] = count
        end
    end

    recipeInfoCache[object.recipeID] = object

    if itemID then
        itemRecipesCache[itemID] = itemRecipesCache[itemID] or { }
        table.insert(itemRecipesCache[itemID], object.recipeID)
    end
end

function TSP:ClearItemCostCache()
    table.wipe(itemCostCache)
end

function TSP:UpdateRecipeInfoCache()
    if C_TradeSkillUI.IsTradeSkillLinked() then
        return
    end

    for i, recipeID in ipairs(C_TradeSkillUI.GetAllRecipeIDs()) do
        local object = C_TradeSkillUI.GetRecipeInfo(recipeID)
        UpdateRecipeInfoCacheObject(object)
    end
end

local GetItemCostRecursive, GetItemCostRecursive

GetRecipeCostRecursive = function (recipeID, seen)
    local object = recipeInfoCache[recipeID]

    if not object.learned then
        return nil
    end

    local cost, source
    for itemID, count in pairs(object.reagents) do
        local c, s = GetItemCostRecursive(itemID, seen)
        if c ~= nil then
            cost = (cost or 0) + c * count
        end
    end
    if cost ~= nil then
        return cost / object.numCreated, "r"
    end
end

GetItemCostRecursive = function (itemID, seen)
    -- Can't depend on ourself, definitely not a winning strategy
    if seen[itemID] ~= nil then
        return
    end

    if itemCostCache[itemID] ~= nil then
        return unpack(itemCostCache[itemID])
    end

    local minCost, minCostSource

    for _,f in ipairs(TSP.costFunctions) do
        local c, s = f(itemID)
        if c and (minCost == nil or c < minCost) then
            minCost, minCostSource = c, s
        end
    end

    seen[itemID] = true
    for _,recipeID in ipairs(itemRecipesCache[itemID] or {}) do
        local c, s = GetRecipeCostRecursive(recipeID, seen)
        if c and (minCost == nil or c < minCost) then
            minCost, minCostSource = c, s
        end
    end

    itemCostCache[itemID] = { minCost, minCostSource }
    return minCost, minCostSource
end

function TSP:GetRecipeItem(recipeID)
    local itemLink = C_TradeSkillUI.GetRecipeItemLink(recipeID)
    local itemID = GetItemInfoFromHyperlink(itemLink)
                    or TSP.scrollData[recipeID]
    return itemID
end

function TSP:GetItemCost(itemID)
    return GetItemCostRecursive(itemID, {})
end

function TSP:GetRecipeCost(recipeID)
    return GetRecipeCostRecursive(recipeID, {})
end

function TSP:GetItemValue(itemID)
    local value, source

    for _,f in ipairs(TSP.valueFunctions) do
        local v, s = f(itemID)
        if v and v > (value or 0) then
            value, source = v, s
        end
    end

    return value, source
end

function TSP:GetRecipeValue(recipeID)
    local item = self:GetRecipeItem(recipeID)
    if item then
        return self:GetItemValue(item)
    end
end
