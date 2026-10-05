# 原生渲染管线与材质集成

本文档说明游戏渲染管线特性、原生 Shader 参数要求以及动态生成 Mesh 的 GPU 提交机制。

---

## 1. 渲染管线概述

终末地客户端采用自研的 `HGRenderPipeline` 高清渲染管线，核心光照着色器为 `HGRP/Lit`。

### 1.1 渲染通道 (Passes)
原生 `HGRP/Lit` 着色器主要包含以下关键渲染通道：
- **HGBuffer**：LightMode 为 `GBuffer`，负责延迟渲染的基础几何与材质属性输出；
- **ShadowCaster**：阴影贴图生成通道；
- **DepthOnly**：深度预渲染通道；
- **RayTracingReflection**：光线追踪反射通道。

### 1.2 Renderer 参数配置
为确保自定义生成的载具模型能正确被场景相机采纳并参与环境光照与阴影计算，动态挂载的 `MeshRenderer` 需配置以下参数：
- `renderingLayerMask`: 1
- `lightModeMask`: 4294967295
- `castShadows`: true
- `receiveShadows`: true
- `motionVectors`: true

---

## 2. 动态 Mesh 的 GPU 提交

动态通过代码生成的 Mesh 需特别注意 Unity 底层图形缓冲区的生命周期与管线同步。

### 2.1 显式上传 (`UploadMeshData`)
- 在主线程完成顶点位置（Position）、法线（Normal）、切线（Tangent）、UV 以及三角面索引的填充与 Bounds 计算后，必须显式调用：
  ```csharp
  mesh.UploadMeshData(false);
  ```
- 此操作立即将 CPU 端的几何数据推送至 GPU 显存，确保在延迟渲染管线各 Pass 执行时顶点缓冲区有效可用。

### 2.2 顶点流与法线支持
- 顶点着色器支持标准三维法线（`Vector3 normal`）与四维切线（`Vector4 tangent`）。
- 顶点数据流解算时自动补齐正交切线基，避免由于平面调色板 UV 面积为零而导致的切线退化问题。
