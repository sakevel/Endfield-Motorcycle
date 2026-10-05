# 工业构建与拆除特效

本文档说明摩托车在召唤出现与收回拆除时使用的工业扫描动画、材质外壳（Shell）以及 VFX 生命周期管理机制。

---

## 1. 特效管线与资源集成

为了与游戏工业风格保持一致，摩托车的召唤与收回动画借用了游戏原生的工业设施建造动效。

### 1.1 原生特效资源
模组复用以下四个原生工业建造特效资产（时长各 2 秒）：
- **出现动效**：`p_factory_appear_cutoff.asset`（网格消融切除）、`p_factory_appear_add.asset`（发光边缘叠加）；
- **消失动效**：`p_factory_disappear_cutoff.asset`、`p_factory_disappear_add.asset`。

### 1.2 包围盒自适应
- 通过 `LuaResourceLoader` 加载特效 ScriptableObject 并在内存中克隆独立副本。
- 开启 `data.useCutoffPosYAutoBounds = true`，自动将原生工业建筑的大尺寸裁切曲线缩放适配至摩托车模型的实际几何包围盒。

---

## 2. 独立高亮外壳 (VFX Shell)

原生工业建筑动效包含一层外凸的发光构建轮廓外壳。为在摩托车模型上完美呈现相同效果，模组构建了独立的视觉 Shell。

### 2.1 外壳网格创建
- 采样阶段为 11 个车体部件创建纯视觉的外壳 GameObjects，共享已上传的 GPU Mesh 几何数据。
- 外壳跟随对应部件的层级、旋转与比例变换，不包含碰撞体。

### 2.2 Shader 与材质适配
- 使用原生 `HGRP/Factory/UnlitFactoryBuildingGrowing` 着色器。
- 将材质参数配置为标准渲染器模式（`FACTORY_ECS = 0`，禁用 `FACTORY_ECS_ON` 关键字），确保顶点裁切与光效沿普通 MeshRenderer 渲染管线正确绘制。
- 动画进行过程中，原生材质控制器按时间曲线驱动 `_CutOffPosY` 参数，呈现自下而上的网格构建与发光扫描效果。

---

## 3. 生命周期与资源管理

### 3.1 EntityRenderHelper 调度
- 通过在车体根节点挂载原生 `Beyond.Gameplay.View.EntityRenderHelper` 统一管理动画生命周期。
- 使用 `AddTimelineEffect` 注册特效，并在主线程 `Tick` 循环中调用 `SampleVFX` 执行采样驱动。

### 3.2 释放与重置
- **单次动画完成**：调用 `Reset()` 暂停当前播放并清理采样器，同时安全销毁材质外壳对象。
- **载具完全收回/销毁**：调用 `ResetAll()` 并注销相关原生句柄，彻底释放所有持有的材质副本与特效引用。
- **状态保护**：召唤与收回动画播放期间禁止执行上车动作，确保动画完整连贯播放。
