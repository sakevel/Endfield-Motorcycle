-- Client source contract validation
local function body(source,name)
    local pattern=name:gsub('(%W)','%%%1')..'[^\n]-<< function(%b())\n(.-)\nend'
    local args,code=source:match(pattern)
    assert(args and code,'missing unique native body '..name)
    return assert(load('return function'..args..'\n'..code..'\nend','@native-fixture-'..name))()
end
local source=native_source('interactoptionctrl.lua'):gsub('\r\n','\n')
local enum={GetHashCode=function()return 1 end}
InteractOptionType={Interactive=enum,Factory={},Crop={}}
InteractOptionIdentifier={CreateInstance=function(type,source,index)
    assert(type==enum and source=='zml.motorcycle.mount' and index==0)
    return {value='zml.motorcycle.mount',type=enum,sourceId=source,subIndex=index,Recycle=function(self)self.recycled=true end}
end}
InteractOptionConst={INTERACT_OPTION_PARSE_OPTION_DATA_CONFIG={},INTERACT_OPTION_CLICK_AUDIO_CONFIG={}}
lume={isarray=function(t)return t[1]~=nil end}
AudioManager={PostEvent=function()end};GameWorld={battle={isSquadInFight=false}}
local ctrl={m_optionInfoMap={},m_nextOptSeqNum=1,m_playingOutInfoTimers={}}
ctrl._ParseOptionData=body(source,'InteractOptionCtrl._ParseOptionData')
ctrl._GetSingleInteractOptionInfo=body(source,'InteractOptionCtrl._GetSingleInteractOptionInfo')
ctrl.AddInteractOption=body(source,'InteractOptionCtrl.AddInteractOption')
ctrl._OnClickOption=body(source,'InteractOptionCtrl._OnClickOption')
local used=0
ctrl:AddInteractOption({type=enum,sourceId='zml.motorcycle.mount',subIndex=0,text='骑乘摩托车',action=function()used=used+1 end})
local info=ctrl.m_optionInfoMap['zml.motorcycle.mount']
assert(info.text=='骑乘摩托车' and info.action and info.typeOrder==1 and info.seqNum==1 and ctrl.m_needUpdateList)
ctrl._TryUpdateShowingList=body(source,'InteractOptionCtrl._TryUpdateShowingList')
local refreshed=0
ctrl._UpdateCurShowingList=function(self,toTop)
    assert(toTop);self.m_needUpdateList=false;refreshed=refreshed+1
end
assert(ctrl:_TryUpdateShowingList() and refreshed==1 and not ctrl:_TryUpdateShowingList(),
    'actual native dirty list flushes once without walking out of a trigger')
ctrl:_OnClickOption('zml.motorcycle.mount');assert(used==1)
ctrl:_OnClickOption('zml.motorcycle.mount');assert(used==1,'native one-action-per-tick gate preserved')
print('PASS: actual current native InteractOption parse/add/click bodies accept Mod callback and preserve native click gate')
local wheel=wheel_native_source:gsub('\r\n','\n')
ZMLBikeWheel=W
Utils.isCurSquadAllDead=function()return false end
local hidden=0
local c={m_clickEnabled=true,m_abilityDataList={{type=W.id}},
    _RefreshWheelShownState=function(_,shown)assert(shown==false);hidden=hidden+1 end}
c._OnSelectorClicked=body(wheel,'GeneralAbilityCtrl._OnSelectorClicked')
c._OnSelectByType=body(wheel,'GeneralAbilityCtrl._OnSelectByType')
c._SetSelectedType=body(wheel,'GeneralAbilityCtrl._SetSelectedType')
c:_OnSelectorClicked(1)
assert(hidden==1 and M.requestedToggle,'native click closes/recover wheel before queuing Mod action')
M.requestedToggle=nil
c:_SetSelectedType(W.id,true)
assert(not M.requestedToggle,'native selected-tool/account setter never receives the Mod sentinel')
c.m_clickEnabled=false;c:_OnSelectorClicked(1)
assert(hidden==1 and not M.requestedToggle,'native click gate retained')
print('PASS: actual patched native R selector closes/recover screen, queues Mod callback and bypasses native selected-type/account mutation')
