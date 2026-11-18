# Axon Python Binding — Examples

ABI 0.10 的 Session 只绑定设备；示例明确创建 EEG 管线和处理后订阅：

```python
from axon import DeliveryKinds

session = axon.new_session(serial)
pipeline = session.create_pipeline("eeg")
pipeline.add_filter(stage)
subscription = pipeline.subscribe(delivery_mask=DeliveryKinds.DATA)
block = subscription.data_queue.get(timeout=3)
subscription.dispose()
pipeline.dispose()
session.dispose()
```

监测器保留这三个对象，停止采集或初始化失败时按订阅、管线、Session 的顺序释放。

本目录包含使用 `axon` Python binding 的示例程序。

## 环境准备

先安装 ABI 0.10.0 的 Axon Python wheel，并选择与你的系统和 CPU 架构匹配的文件。旧版 ABI 不兼容：

推荐使用 `uv` 管理 Python 环境。

```shell
cd axon-examples\python
uv venv
uv pip install --reinstall path/to/your/wheel/axon-0.10.0-py3-none-win_amd64.whl
```

上面的文件名以 Windows x64 为例；macOS 和 Linux 请使用对应平台的 ABI 0.10.0 wheel。

安装后可用 `uv pip install -r requirements.txt` 检查绑定版本。语言绑定和原生库必须来自同一份 SDK；不能混用旧 wheel 内的库与当前源码绑定。

### 相邻源码开发（Windows）

将 `axon` 与 `axon-examples` 放在同一目录，在本目录执行：

```powershell
pwsh ../../axon/scripts/build-native.ps1 -Profile debug
uv venv
uv pip install -e ../../axon/bindings/python
$env:AXON_LIB_PATH = (Resolve-Path ../../axon/outputs/native/windows/debug/axon.dll).Path
uv run python lychee_monitor.py
```

macOS/Linux 使用同一构建脚本，并将 `AXON_LIB_PATH` 指向相应平台产物。升级源码后重新构建原生库。

### 检查

```powershell
uv run python -m unittest discover -s tests -v
$env:AXON_RUN_NATIVE_TESTS = "1"
uv run python -m unittest discover -s tests -v
```

第二次运行包含原生模拟器、处理管线和队列收样测试，需先准备匹配的运行库。未设置 `AXON_RUN_NATIVE_TESTS=1` 时跳过原生测试。

## lychee_monitor.py — Lychee EEG 实时波形监测

桌面监测示例：自动发现 Lychee 设备、选择传感器，并以经典 EEG 网格样式显示实时滚动波形。

### 快速开始

```bash
# 无硬件或有硬件
uv run python lychee_monitor.py

```

打开窗口后，点击“添加模拟器”即可创建一个内置模拟数据源；Lychee 硬件仍会自动发现。设备出现在顶部列表后选择设备，再点击“开始采集”。监测器订阅设备的 `eeg` 均匀采样流；没有该流或流为非均匀采样时会提示无法启动。窗口关闭时会停止 session、模拟器与监听器。

模拟器使用 ABI 型号值 `DeviceModel(0)`（BCI100，3 通道、250 Hz）。
已发布的 0.10.0 wheel 将此枚举成员命名为 `LYCHEE_PFC`，源码绑定中名为
`LYCHEE_BCI100`；按 ABI 值选择可兼容这两种名称。

### lychee 设备 serial 格式

lychee 设备 serial 为 6 位大写十六进制（如 `A1B2C3`），  
通过 `axon_device_callback` 设备上线事件自动获得，并从页面顶部的设备列表选择。
