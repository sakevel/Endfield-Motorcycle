local ctrl={isPCPanel=true}
M.show(ctrl)
assert(PUBLIC.get('motorcycle').mount_key==nil)
local K=ZMLKeybinds
for _,id in ipairs({'dismount','jump','forward','reverse','left','right','brake'}) do assert(K.find('motorcycle',id)) end
assert(not K.find('motorcycle','summon'),'R wheel stays native, no duplicate R binding')
local jump=K.find('motorcycle','jump')
assert(K._stage(jump.id,1,'J'));assert(K._save())
local dismount=K.find('motorcycle','dismount')
assert(K._stage(dismount.id,1,'F11'));assert(K._save())
local forward=K.find('motorcycle','forward')
assert(K._stage(forward.id,1,'UpArrow'));assert(K._save())
MOCK.setAxes(0,0)
M.summon();if M.presentation then M.finishPresentation() end
M.mount();assert(M.lease)
MOCK.keysHeld.UpArrow=true;MOCK.run('Tick',.02)
assert(M.lease.throttle==1,'new binding drives the actual production vehicle')
MOCK.keysHeld.UpArrow=nil;MOCK.keysHeld.W=true;MOCK.run('Tick',.02)
assert(M.lease.throttle==0,'old default is no longer handled by the mod')
MOCK.keysHeld.W=nil
MOCK.keysDown.Space=true;MOCK.run('Tick',.02);assert(not M.lease.flight)
MOCK.keysDown.J=true;MOCK.run('Tick',.02);assert(M.lease.flight,'remapped jump invokes actual flight pipeline')
M.close(ctrl);MOCK.run('Tick');MOCK.run('Tick')
GameInstance.playerController.mainCharacter=MOCK.newCharacter()
M.show(ctrl);M.summon();if M.presentation then M.finishPresentation() end
M.mount();assert(M.lease)
MOCK.keysDown.F7=true;MOCK.run('Tick',.02);assert(M.lease)
MOCK.keysDown.F11=true;MOCK.run('Tick',.02);assert(not M.lease,'new dismount, not removed schema/hardcoded F7')
M.close(ctrl);MOCK.keysDown={};MOCK.keysHeld={}
K._reset();assert(K._save())
