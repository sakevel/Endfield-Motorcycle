-- Keybinds input test model
local disk
ZMLKeybinds=keybind_factory({
    owner=function(id)return PUBLIC.mod(id) and id end,
    validKey=function(s)return s:match('^[A-Za-z][A-Za-z0-9]*$')~=nil end,
    read=function()return disk end,write=function(s)disk=s;return true end,
    allowed=function()return CS.UnityEngine.Application.isFocused and GameInstance.isInGameplay end,
    down=function(key)
        local held=MOCK.keysHeld[key]
        local edge=MOCK.keysDown[key];MOCK.keysDown[key]=nil
        if held or edge then return true end
        -- Existing motion fixtures express a physical PC direction as raw axes.
        -- Dedicated migration tests below use remapped held keys instead.
        local raw=GameInstance.playerController.rawMoveAxis
        return (key=='W' and raw.y>0) or (key=='S' and raw.y<0) or
            (key=='D' and raw.x>0) or (key=='A' and raw.x<0) or false
    end})
