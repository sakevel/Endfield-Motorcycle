# 原生客户端接口与生命周期契约

本文档记录终末地客户端的底层架构、资源虚拟文件系统 (VFS)、原生移动组件以及生命周期契约。

---

## 1. 客户端架构与资源管线

### 1.1 虚拟文件系统 (VFS)
- 游戏资源采用分层覆盖机制，优先从 `Persistent` 目录检索，未命中时回退至 `StreamingAssets`。
- 关键逻辑脚本（如 `BattleActionCtrl`、`UIManager`、`GeneralAbilityCtrl` 等）均经过两层封装（BLC 容器与 Lua 字节码加密）。

### 1.2 资源加载器
- 原生模块通过 `require_ex("Common/Utils/LuaResourceLoader").LuaResourceLoader()` 实例化资源加载器。
- 支持 `LoadMesh`、`LoadMaterial` 与 `LoadScriptableObject` 等标准接口，并由加载器统一管理引用计数与资源卸载。

---

## 2. 原生移动与角色组件契约

### 2.1 玩家控制器与角色层级
- 核心访问路径：`GameInstance.playerController -> PlayerController.mainCharacter`。
- 角色实体基础属性与组件：
  - `Entity.movementComponent`：负责物理位移、加速度与移动模式控制；
  - `Entity.rootCom`：持有角色的根 Transform 与底层 GameObject；
  - `Entity.characterAnimCom`：包含角色动画与 IK 逆向动力学控制器（`GrounderBipedIK` / `BipedIK`）。

### 2.2 速度覆盖句柄 (Override Speed Handle)
- `MovementComponent.SetOverrideSpeed(float speed, float accel)` 返回唯一整数句柄，用于接管角色的移动速度上限；
- `MovementComponent.RemoveOverrideSpeed(uint32 handle)` 注销对应句柄，安全恢复角色的原生移动速度。

### 2.3 移动模式状态机
- `MovementComponent.MoveMode` 枚举定义角色的运动状态：
  - `Grounded`、`StepClimbing`、`Pivot`、`TurnStart` 为常规地面移动状态；
  - `Falling` 与特定跳跃状态在容错时间窗口内被允许维持乘骑；
  - 遭受击退（Blown）、下落攻击（Plunge）或进入过场时自动触发脱离。

---

## 3. 生命周期与更新循环 (LuaUpdate)

游戏的主线程循环通过 `Common/Core/LuaUpdate` 统一调度：
- 分为 `Tick`、`LateTick`、`TailTick` 与 `RenderDone` 四个阶段；
- 模组的载具位移推算在 `Tick` 阶段下达导航指令，在 `TailTick` 阶段收集物理移动结果并积分偏航角；
- 界面隐藏或生命周期销毁时安全解绑所有注册的 Tick 任务与事件监听。
