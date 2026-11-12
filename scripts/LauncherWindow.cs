using System;
using System.Runtime.InteropServices;

namespace ZeldaOotLauncher
{
    public static class WindowControl
    {
        private const int ResizeStep = 20;
        private const uint GW_OWNER = 4;
        private const uint SWP_NOMOVE = 0x0002;
        private const uint SWP_NOZORDER = 0x0004;
        private const uint SWP_NOACTIVATE = 0x0010;
        private const uint SWP_NOOWNERZORDER = 0x0200;
        private const uint SWP_ASYNCWINDOWPOS = 0x4000;

        [StructLayout(LayoutKind.Sequential)]
        internal struct Rect
        {
            internal int Left;
            internal int Top;
            internal int Right;
            internal int Bottom;

            internal int Width { get { return Right - Left; } }
            internal int Height { get { return Bottom - Top; } }
        }

        public sealed class Window
        {
            internal readonly IntPtr Handle;
            internal readonly uint ProcessId;
            internal readonly Rect Bounds;

            internal Window(IntPtr handle, uint processId, Rect bounds)
            {
                Handle = handle;
                ProcessId = processId;
                Bounds = bounds;
            }
        }

        private delegate bool EnumWindowsCallback(IntPtr window, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern bool EnumWindows(EnumWindowsCallback callback, IntPtr parameter);

        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);

        [DllImport("user32.dll")]
        private static extern IntPtr GetWindow(IntPtr window, uint command);

        [DllImport("user32.dll")]
        private static extern bool IsWindowVisible(IntPtr window);

        [DllImport("user32.dll")]
        private static extern bool IsIconic(IntPtr window);

        [DllImport("user32.dll")]
        private static extern bool GetWindowRect(IntPtr window, out Rect bounds);

        [DllImport("user32.dll")]
        private static extern bool GetClientRect(IntPtr window, out Rect bounds);

        [DllImport("user32.dll")]
        private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y,
            int width, int height, uint flags);

        [DllImport("user32.dll")]
        private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);

        private static bool IsGameWindow(IntPtr window, uint processId)
        {
            uint owner;
            return GetWindowThreadProcessId(window, out owner) != 0 && owner == processId
                && IsWindowVisible(window) && !IsIconic(window) && GetWindow(window, GW_OWNER) == IntPtr.Zero;
        }

        public static Window Find(int processId, int clientWidth, int clientHeight)
        {
            // Per-monitor DPI awareness keeps the dimensions in physical pixels.
            IntPtr previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
            try
            {
                Window result = null;
                bool ambiguous = false;
                EnumWindows(delegate(IntPtr window, IntPtr parameter)
                {
                    Rect client;
                    Rect bounds;
                    if (!IsGameWindow(window, (uint)processId) || !GetClientRect(window, out client)
                        || client.Width != clientWidth || client.Height != clientHeight
                        || !GetWindowRect(window, out bounds))
                        return true;

                    if (result != null)
                    {
                        ambiguous = true;
                        return false;
                    }
                    result = new Window(window, (uint)processId, bounds);
                    return true;
                }, IntPtr.Zero);
                return ambiguous ? null : result;
            }
            finally
            {
                if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous);
            }
        }

        public static bool Shrink(Window window)
        {
            return Resize(window, false);
        }

        public static bool Restore(Window window)
        {
            return Resize(window, true);
        }

        private static bool Resize(Window window, bool restore)
        {
            IntPtr previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
            try
            {
                Rect current;
                Rect original = window.Bounds;
                if (!IsGameWindow(window.Handle, window.ProcessId) || !GetWindowRect(window.Handle, out current)
                    || current.Left != original.Left || current.Top != original.Top)
                    return false;

                bool originalSize = current.Width == original.Width && current.Height == original.Height;
                bool smallerSize = current.Width == original.Width - ResizeStep
                    && current.Height == original.Height - ResizeStep;
                if (!originalSize && !(restore && smallerSize)) return false;

                // The game processes both requests on its own GUI thread. Do not move
                // or activate its window, change its style, or send keyboard input.
                int delta = restore ? 0 : ResizeStep;
                return SetWindowPos(window.Handle, IntPtr.Zero, 0, 0,
                    original.Width - delta, original.Height - delta,
                    SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER | SWP_ASYNCWINDOWPOS);
            }
            finally
            {
                if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous);
            }
        }
    }
}
