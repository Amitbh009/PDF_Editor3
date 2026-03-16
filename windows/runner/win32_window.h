#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// OnCreate/OnDestroy methods. Subclasses should not have their own WindowProc.
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size to will treat the target DPI as 96 = 100%.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  // Subclasses can override this to handle when the OS requests destruction
  // of the window. The window handle is still valid at this point.
  virtual void OnDestroy();

  // Subclasses can override this to handle window creation.
  virtual bool OnCreate();

  // Handles Win32 messages. Subclasses can override this to handle
  // additional messages.
  virtual LRESULT
  MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                 LPARAM const lparam) noexcept;

  // Called when the OS requests the window to show itself (e.g. after initial
  // creation or to bring it back from a minimized state).
  void Show();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the legacy Win32 (non-HWND-hosted) bits of
  // Flutter rendering work correctly on HiDPI displays.
  static LRESULT CALLBACK WndProc(HWND const window, UINT const message,
                                   WPARAM const wparam,
                                   LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|.
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  bool quit_on_close_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // handle for hosted content window.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
