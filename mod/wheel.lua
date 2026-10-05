-- GeneralAbility tool wheel slot adapter.
local W={id=-73001}
local U=CS.UnityEngine
-- ZML_WHEEL_ICON_DATA
local function bridge()
    local r=hg.loadedModules["ZML/Motorcycle"]
    return r and r.env.Motorcycle
end
local function diag(event,err)
    local m=bridge()
    if m and m.api then pcall(m.api.report,"motorcycle",event) end
    if err then pcall(function() logger.error("ZML Motorcycle: "..event..": "..tostring(err):sub(1,400)) end) end
end
local function icon()
    if W.sprite and not W.sprite:Equals(nil) then return W.sprite end
    local tex=U.Texture2D(2,2)
    W.texture=tex
    assert(U.ImageConversion.LoadImage(tex,CS.System.Convert.FromBase64String(WHEEL_ICON_BASE64),false),"wheel PNG rejected")
    W.sprite=assert(U.Sprite.Create(tex,U.Rect(0,0,tex.width,tex.height),U.Vector2(.5,.5),100),"wheel sprite unavailable")
    return W.sprite
end
function W.release(ctrl)
    if W.owner~=ctrl then return end
    if W.sprite then U.Object.Destroy(W.sprite) end
    if W.texture then U.Object.Destroy(W.texture) end
    W.sprite,W.texture,W.owner=nil,nil,nil
end
function W.register(ctrl)
    local list,map=ctrl.m_abilityDataList,ctrl.m_abilityDataMap
    if not list or not map then return end
    map[W.id]=nil
    for i=1,7 do if list[i] and list[i].type==W.id then list[i]=nil end end
    local m=bridge()
    if not m or not m.wheelAvailable() then return end
    for i=1,7 do
        if not list[i] then
            local data={type=W.id,index=i,name="摩托车",isForbidSelect=false,zmlMotorcycle=true}
            list[i]=data;map[W.id]=data
            diag("wheel_registered");return
        end
    end
    -- Select available tool wheel slot
    diag("wheel_full")
end
function W.refresh(ctrl)
    local old=ctrl.m_abilityDataMap and ctrl.m_abilityDataMap[W.id]
    local oldIndex=old and old.index
    W.register(ctrl)
    local current=ctrl.m_abilityDataMap and ctrl.m_abilityDataMap[W.id]
    local newIndex=current and current.index
    local function update(i)
        if i then
            local cell=ctrl.m_abilityCells:GetItem(i)
            if cell then ctrl:_UpdateSelectorCellInfo(cell,i) end
        end
    end
    update(oldIndex)
    if newIndex~=oldIndex then update(newIndex) end
end
function W.cell(ctrl,cell,index)
    local data=ctrl.m_abilityDataList[index]
    if not data or data.type~=W.id then return false end
    local ok,err=pcall(function()
        W.owner=ctrl
        local sprite=icon()
        data.cell=cell
        for _,ability in ipairs({cell.ability,cell.shadowAbility}) do
            ability:InitGeneralAbilityCell() -- native locked state; explicitly retire stale tasks below
            ability.m_cdUpdateThread=ability:_ClearCoroutine(ability.m_cdUpdateThread)
            ability.m_itemUpdateThread=ability:_ClearCoroutine(ability.m_itemUpdateThread)
            ability.m_abilityRuntimeData=nil
            ability.m_abilityType=-1
            ability.ignoreStateChangeEvent=true
            local v=ability.view
            v.lockedNode.gameObject:SetActive(false)
            v.normalNode.gameObject:SetActive(true)
            v.cdNode.gameObject:SetActive(false)
            v.itemCountNode.gameObject:SetActive(false)
            v.icon.sprite=sprite
            v.normalNodeCanvasGroup.alpha=1
            v.normalNodeCanvasGroup.color=v.config.NORMAL_COLOR
        end
        cell.shadowAbility.view.gameObject:SetActive(true)
        cell.uiStateCtrl:SetState("NormalState")
        cell.uiStateCtrl:SetState("HighLightNormalColor")
        cell.gameObject.name="Ability_ZML_Motorcycle"
        cell.button.enabled=true
        cell.animationWrapper:PlayWithTween("generalability_selector_cell_default")
    end)
    if not ok then
        data.isForbidSelect=true;cell.button.enabled=false
        diag("wheel_cell_failed",err)
    end
    return true
end
function W.select(type)
    if type~=W.id then return false end
    local m=bridge()
    if m then m.requestToggle() end
    return true
end
function W.hover(ctrl,type)
    if type~=W.id then return false end
    local m=bridge()
    ctrl.view.hoverAbilityNameTxt.text=(m and m.isNear()) and "收回摩托车" or "召唤摩托车"
    local enabled=m and m.wheelAvailable() and not m.presentation
    ctrl.view.middleStateCtrl:SetState(enabled and "SelectState" or "DisableState")
    return true
end
return W
