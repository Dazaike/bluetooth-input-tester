# Bluetooth Input Tester

Windows tool that shows which device sent each input. Use it to check that a Bluetooth remote really delivers button presses, not just that it says "connected".

## Usage

Download `BtTester-v1.0.0.zip` from the Releases page, extract it, and double-click `Run.bat`. Or run `BtTester.ps1` with `powershell -STA -File BtTester.ps1`.

Each input prints a line like:

```
14:02:11.532  Input received from Bluetooth address AA:BB:CC:DD:EE:FF (VID 054C PID 09CC)  ->  KEY down VolumeUp (VK 0xAF)
```

- Keyboard-style buttons show the key name.
- Other HID buttons show the raw report bytes.
- Mouse buttons and wheel are logged; movement at most once per second.
- Non-Bluetooth devices are labelled "Non-Bluetooth input device".
- It logs input even when the window is not focused.

Requires Windows with PowerShell 5.1 (built in). Version: 1.0.0. See [CHANGELOG.md](CHANGELOG.md).
