#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>
#include <cstdint>
#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
// DWMWA_CAPTION_COLOR and DWMWA_TEXT_COLOR, available on Windows 11.
constexpr DWORD kCaptionColor = 35;
constexpr DWORD kCaptionTextColor = 36;

std::optional<COLORREF> DecodeColor(const flutter::EncodableValue& value) {
  const auto* rgb = std::get_if<int32_t>(&value);
  if (!rgb || *rgb < 0 || *rgb > 0xFFFFFF) {
    return std::nullopt;
  }
  return RGB((*rgb >> 16) & 0xFF, (*rgb >> 8) & 0xFF, *rgb & 0xFF);
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  caption_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "todo/windows_caption",
          &flutter::StandardMethodCodec::GetInstance());
  caption_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "setColors") {
      result->NotImplemented();
      return;
    }
    const auto* colors = std::get_if<flutter::EncodableList>(call.arguments());
    if (!colors || colors->size() != 2) {
      result->Error("invalid_colors", "Expected caption and text RGB values.");
      return;
    }
    const auto caption = DecodeColor((*colors)[0]);
    const auto text = DecodeColor((*colors)[1]);
    if (!caption || !text) {
      result->Error("invalid_colors", "Expected RGB values from 0 to 0xFFFFFF.");
      return;
    }
    if (SUCCEEDED(DwmSetWindowAttribute(GetHandle(), kCaptionColor, &*caption,
                                        sizeof(COLORREF)))) {
      DwmSetWindowAttribute(GetHandle(), kCaptionTextColor, &*text,
                            sizeof(COLORREF));
    }
    result->Success();
  });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (caption_channel_) {
    caption_channel_->SetMethodCallHandler(nullptr);
    caption_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
