local U=CS.UnityEngine
local ctrl={isPCPanel=true}
local ch=GameInstance.playerController.mainCharacter
local pc=GameInstance.playerController
local root=ch.rootCom.transform
local position=root.position
M.show(ctrl);M.summon();M.finishPresentation();MOCK.run('Tick')
local box=M.bodyCollider
assert(box and box.size.z>box.size.x and not box.isTrigger and not box.enabled)
root.position=position+U.Vector3(4,0,0);MOCK.run('Tick')
assert(box.enabled,'parked volume becomes solid after original overlap clears')
root.position=position;MOCK.run('Tick')
assert(box.enabled,'approaching again cannot turn the parked collider off')
M.mount();assert(M.lease and not box.enabled,'no rider self-collision; driving uses swept volume')
local lease=M.lease
pc.rawMoveAxis=U.Vector3(0,1,0);MOCK.run('Tick',.02)
assert(not lease.collisionBlocked and lease.lastCommand.magnitude>.9)
MOCK.collisionWall=true;MOCK.run('Tick',.02)
assert(lease.collisionBlocked and lease.lastCommand.magnitude==0 and lease.speed==0 and lease.speedAccel==96)
MOCK.collisionWall=nil;MOCK.run('Tick',.02)
assert(not lease.collisionBlocked and lease.lastCommand.magnitude>.9,'drive resumes after obstacle is clear')
pc.rawMoveAxis=U.Vector3(0,-1,0);MOCK.collisionWall=true;MOCK.run('Tick',.02)
assert(lease.collisionBlocked and MOCK.lastCast.direction.z<0,'reverse casts behind the full-length bike')
MOCK.contactNormal=MOCK.lastCast.direction;MOCK.run('Tick',.02)
assert(not lease.collisionBlocked,'retreating from contact is not blocked by the cast normal')
MOCK.collisionWall=nil;MOCK.contactNormal=nil
pc.rawMoveAxis=U.Vector3(1,1,0);MOCK.overlapWall=true;MOCK.run('Tick',.02)
assert(lease.collisionBlocked,'turning endpoint checks the full rotated body, not only the player capsule')
MOCK.overlapWall=nil;MOCK.castOwn=true;MOCK.run('Tick',.02)
assert(not lease.collisionBlocked,'own collider excluded without changing global physics masks')
MOCK.castOwn=nil;MOCK.collisionSaturated=true;MOCK.run('Tick',.02)
assert(lease.collisionBlocked,'saturated buffer fails closed')
MOCK.collisionSaturated=nil
local scale=tonumber(PUBLIC.get('motorcycle').scale)
assert(PUBLIC.set('motorcycle','scale',1.2));MOCK.run('TailTick',.02);MOCK.run('Tick',.02)
assert(math.abs(MOCK.lastCast.half.z-1.12*1.2)<.00001,'hot scale updates the collision envelope')
assert(PUBLIC.set('motorcycle','scale',scale))
MOCK.failCollisionQuery=true;MOCK.run('Tick',.02)
assert(not M.lease and M.faulted and ch.movementComponent.handles[77]=='FOREIGN','binding failure restores only own movement/pose')
MOCK.failCollisionQuery=nil;pc.rawMoveAxis=U.Vector3();M.close(ctrl)
assert(box.gameObject.destroyed and not box.enabled,'own volume destroyed and disabled before deferred Destroy')
root.position=position
M.show(ctrl);MOCK.failCollider=true;M.summon()
assert(not M.vehicle and not M.lease and M.phase=='absent','partial collider creation rolls back model allocations')
MOCK.failCollider=nil;M.close(ctrl)
assert(MOCK.countUpdates()==0)
print('PASS: owned parked box, no overlap trap, full-body forward/reverse sweep, turning overlap, self exclusion, saturation, hot scale and failure cleanup')
