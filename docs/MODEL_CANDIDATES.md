# 外部模型选型与授权说明

本模组采用合规开源 / 知识共享 (Creative Commons) 授权的外部 3D 模型资产，以便于独立打包与自由分发。

---

## 1. 采用的模型资产

- **模型名称**：[Low-Poly Motorcycle #2](https://sketchfab.com/3d-models/low-poly-motorcycle-2-9e79295e99654e2a9fa930b5139a7d84)
- **作者**：Sidra
- **授权协议**：[Creative Commons Attribution 4.0 International (CC BY 4.0)](https://creativecommons.org/licenses/by/4.0/)
- **模型特征**：
  - 现代低多边形街车造型；
  - 包含独立的车身、前后车轮、转向前叉架与单侧边撑支架分件，适合进行骨骼绑定与转向/轮转解算；
  - 经格式转换与去重处理后包含 11 个材质分件、29,204 个渲染顶点、23,016 个三角面；
  - 重新调整为符合游戏风格的白黄工业配色（详见 [MODEL_INTEGRATION.md](MODEL_INTEGRATION.md)）。

完整许可与归属声明请参阅发行包根目录的 `THIRD_PARTY_NOTICES.md` 及 `licenses/`。

---

## 2. 备选模型评估记录

在选型阶段对多个公开资产进行了几何结构与可分发性评估：

| 候选资产 | 授权形式 | 顶点/面数 | 评估结论 |
|---|---|---|---|
| **Sidra / Low-Poly Motorcycle #2** | CC BY 4.0 | ~23k 面 | **最终选用**。分件清晰、结构完整、比例协调。 |
| **3D Assets / Road sportbike** | CC0 1.0 | ~17 Meshes | 几何精细度较低，仅作为原型技术验证参考。 |
| **ROH3D / Low Poly Motorcycle 001** | CC BY 4.0 | ~5.5k 面 | 复古长前叉巡航风格，与游戏工业风格契合度较低。 |
| **Robert Doman / Low Poly WW2** | Sketchfab Standard | 未开放商用 | 商业授权受限，不符合开源自由分发要求。 |
