# Axon Python Binding — Examples

本目录包含使用 `axon` Python binding 的示例程序。

## 环境准备

先安装 ABI 0.2.0 的 Axon Python wheel，并选择与你的系统和 CPU 架构匹配的文件。旧版 ABI 不兼容：

推荐使用 `uv` 管理 Python 环境。

```shell
cd axon-examples\python
uv venv
uv pip install --reinstall path/to/your/wheel/axon-0.2.0-py3-none-win_amd64.whl
```

上面的文件名以 Windows x64 为例；macOS 和 Linux 请使用对应平台的 ABI 0.2.0 wheel。

## lychee_monitor.py — Lychee EEG 实时波形监测

桌面监测示例：自动发现 Lychee 设备、选择传感器，并以经典 EEG 网格样式显示实时滚动波形。

### 快速开始

```bash
# 无硬件或有硬件
uv run python lychee_monitor.py

```

打开窗口后，点击“添加模拟器”即可创建一个内置模拟数据源；Lychee 硬件仍会自动发现。设备出现在顶部列表后选择设备，再点击“开始采集”。监测器订阅设备的 `eeg` 均匀采样流；没有该流或流为非均匀采样时会提示无法启动。窗口关闭时会停止 session、模拟器与监听器。

### lychee 设备 serial 格式

lychee 设备 serial 为 6 位大写十六进制（如 `A1B2C3`），  
通过 `axon_device_callback` 设备上线事件自动获得，并从页面顶部的设备列表选择。
