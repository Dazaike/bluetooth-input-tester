param([switch]$CompileOnly)

$src = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows.Forms;

public class BtForm : Form
{
    const int WM_INPUT = 0x00FF;
    const uint RID_INPUT = 0x10000003;
    const uint RIDI_DEVICENAME = 0x20000007;
    const uint RIDEV_INPUTSINK = 0x100;

    [StructLayout(LayoutKind.Sequential)]
    struct RAWINPUTDEVICE { public ushort usUsagePage; public ushort usUsage; public uint dwFlags; public IntPtr hwndTarget; }

    [DllImport("user32.dll", SetLastError = true)]
    static extern bool RegisterRawInputDevices(RAWINPUTDEVICE[] p, uint n, uint size);
    [DllImport("user32.dll")]
    static extern uint GetRawInputData(IntPtr h, uint cmd, byte[] data, ref uint size, uint hdrSize);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    static extern uint GetRawInputDeviceInfo(IntPtr dev, uint cmd, StringBuilder data, ref uint size);

    TextBox log = new TextBox();
    Label status = new Label();
    Dictionary<IntPtr, string> names = new Dictionary<IntPtr, string>();
    DateTime lastMove = DateTime.MinValue;

    public BtForm()
    {
        Text = "Bluetooth Input Tester";
        Width = 900; Height = 600;
        log.Multiline = true; log.ReadOnly = true; log.ScrollBars = ScrollBars.Vertical;
        log.Dock = DockStyle.Fill; log.Font = new Font("Consolas", 11);
        log.BackColor = Color.Black; log.ForeColor = Color.LightGreen;
        status.Dock = DockStyle.Top; status.Height = 28; status.TextAlign = ContentAlignment.MiddleLeft;
        status.Text = "  Press buttons on the remote. Window works in background too.";
        Button clear = new Button(); clear.Text = "Clear"; clear.Dock = DockStyle.Bottom; clear.Height = 32;
        clear.Click += delegate { log.Clear(); };
        Controls.Add(log); Controls.Add(status); Controls.Add(clear);
    }

    protected override void OnHandleCreated(EventArgs e)
    {
        base.OnHandleCreated(e);
        ushort[,] targets = { { 1, 6 }, { 1, 2 }, { 1, 4 }, { 1, 5 }, { 1, 0x80 }, { 0x0C, 1 }, { 0x0B, 1 }, { 0xFF00, 1 } };
        RAWINPUTDEVICE[] r = new RAWINPUTDEVICE[targets.GetLength(0)];
        for (int i = 0; i < r.Length; i++)
        {
            r[i].usUsagePage = targets[i, 0]; r[i].usUsage = targets[i, 1];
            r[i].dwFlags = RIDEV_INPUTSINK; r[i].hwndTarget = Handle;
        }
        if (!RegisterRawInputDevices(r, (uint)r.Length, (uint)Marshal.SizeOf(typeof(RAWINPUTDEVICE))))
            Append("WARNING: RegisterRawInputDevices failed, error " + Marshal.GetLastWin32Error());
        Append("Listening for input from all devices...");
    }

    void Append(string s)
    {
        log.AppendText(DateTime.Now.ToString("HH:mm:ss.fff") + "  " + s + "\r\n");
    }

    string Describe(IntPtr dev)
    {
        string v;
        if (names.TryGetValue(dev, out v)) return v;
        uint size = 0;
        GetRawInputDeviceInfo(dev, RIDI_DEVICENAME, null, ref size);
        StringBuilder sb = new StringBuilder((int)size + 1);
        GetRawInputDeviceInfo(dev, RIDI_DEVICENAME, sb, ref size);
        string path = sb.ToString();
        Match m = Regex.Match(path, @"_REV&[0-9A-Fa-f]{4}_([0-9A-Fa-f]{12})", RegexOptions.IgnoreCase);
        if (!m.Success) m = Regex.Match(path, @"DEV_([0-9A-Fa-f]{12})", RegexOptions.IgnoreCase);
        bool bt = path.IndexOf("00001124-0000-1000-8000-00805f9b34fb", StringComparison.OrdinalIgnoreCase) >= 0
               || path.IndexOf("00001812-0000-1000-8000-00805f9b34fb", StringComparison.OrdinalIgnoreCase) >= 0
               || path.IndexOf("BTH", StringComparison.OrdinalIgnoreCase) >= 0;
        Match vp = Regex.Match(path, @"VID&(?:0002|0001)?([0-9A-Fa-f]{4})_PID&([0-9A-Fa-f]{4})", RegexOptions.IgnoreCase);
        if (!vp.Success) vp = Regex.Match(path, @"VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})", RegexOptions.IgnoreCase);
        string ids = vp.Success ? " (VID " + vp.Groups[1].Value + " PID " + vp.Groups[2].Value + ")" : "";
        if (bt && m.Success)
        {
            string a = m.Groups[1].Value.ToUpper();
            v = "Input received from Bluetooth address " + Regex.Replace(a, "(..)(?!$)", "$1:") + ids;
        }
        else if (bt) v = "Input received from Bluetooth device (address not in path)" + ids + "  " + path;
        else v = "Non-Bluetooth input device" + ids + "  " + path;
        names[dev] = v;
        return v;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WM_INPUT) { try { Handle_Input(m.LParam); } catch (Exception ex) { Append("error: " + ex.Message); } }
        base.WndProc(ref m);
    }

    void Handle_Input(IntPtr h)
    {
        uint hdr = (uint)(IntPtr.Size * 2 + 8);
        uint size = 0;
        GetRawInputData(h, RID_INPUT, null, ref size, hdr);
        byte[] b = new byte[size];
        if (GetRawInputData(h, RID_INPUT, b, ref size, hdr) != size) return;
        uint type = BitConverter.ToUInt32(b, 0);
        IntPtr dev = (IntPtr)(IntPtr.Size == 8 ? BitConverter.ToInt64(b, 8) : BitConverter.ToInt32(b, 8));
        int o = (int)hdr;
        string who = Describe(dev);
        string what;
        if (type == 1) // keyboard
        {
            ushort flags = BitConverter.ToUInt16(b, o + 2);
            ushort vk = BitConverter.ToUInt16(b, o + 6);
            what = "KEY " + ((flags & 1) == 0 ? "down" : "up  ") + " " + ((Keys)vk) + " (VK 0x" + vk.ToString("X2") + ")";
        }
        else if (type == 0) // mouse
        {
            ushort bf = BitConverter.ToUInt16(b, o + 4);
            short wheel = BitConverter.ToInt16(b, o + 6);
            if (bf == 0)
            {
                if ((DateTime.Now - lastMove).TotalMilliseconds < 1000) return;
                lastMove = DateTime.Now; what = "MOUSE movement";
            }
            else what = "MOUSE buttons 0x" + bf.ToString("X") + (wheel != 0 ? " wheel " + wheel : "");
        }
        else // generic HID
        {
            uint sz = BitConverter.ToUInt32(b, o), cnt = BitConverter.ToUInt32(b, o + 4);
            int n = (int)Math.Min(sz * cnt, (uint)(b.Length - o - 8));
            what = "HID report: " + BitConverter.ToString(b, o + 8, n).Replace("-", " ");
        }
        Append(who + "  ->  " + what);
    }

    [STAThread]
    public static void Run() { Application.EnableVisualStyles(); Application.Run(new BtForm()); }
}
'@

Add-Type -TypeDefinition $src -ReferencedAssemblies System.Windows.Forms, System.Drawing
if ($CompileOnly) { "compiled OK"; return }
[BtForm]::Run()
