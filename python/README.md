# Axon Python Binding — Examples

本目录包含使用 `axon` Python binding 的示例程序。

## 环境准备

先安装与你的系统和 CPU 架构匹配的 Axon wheel：

推荐使用 `uv` 管理 Python 环境。

```shell
cd axon-examples\python
uv venv
uv pip install <axon-*.whl 的绝对路径>
```

## lychee_monitor.py — Lychee EEG 实时波形监测

桌面监测示例：自动发现 Lychee 设备、选择传感器，并以经典 EEG 网格样式显示实时滚动波形。

### 快速开始

```bash
# 无硬件（模拟器模式）
uv run python lychee_monitor.py --sim

# 有 lychee 硬件（配网完成后，局域网内上电后自动发现）
uv run python lychee_monitor.py

# 已知 serial
uv run python lychee_monitor.py --serial AABBCC
```

打开窗口后，从顶部的传感器列表选择设备，再点击“开始采集”。窗口关闭时会停止 session 与监听器。

### lychee 设备 serial 格式

lychee 设备 serial 为 6 位大写十六进制（如 `A1B2C3`），  
通过 `axon_device_callback` 设备上线事件自动获得，或在 `--serial` 参数中直接指定。
