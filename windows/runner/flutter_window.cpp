#include "flutter_window.h"

#include <optional>
#include <iterator>
#include <algorithm>
#include <commdlg.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

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
  child_job_ = CreateJobObjectW(nullptr, nullptr);
  if (child_job_) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(child_job_, JobObjectExtendedLimitInformation,
                                 &limits, sizeof(limits))) {
      CloseHandle(child_job_);
      child_job_ = nullptr;
    }
  }
  flutter::MethodChannel<flutter::EncodableValue> process_channel(
      flutter_controller_->engine()->messenger(), "fap_helper/process",
      &flutter::StandardMethodCodec::GetInstance());
  process_channel.SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() != "trackChild" || call.arguments() == nullptr) {
      result->NotImplemented();
      return;
    }
    const auto* pid = std::get_if<int32_t>(call.arguments());
    HANDLE child = pid ? OpenProcess(PROCESS_SET_QUOTA | PROCESS_TERMINATE,
                                     FALSE, static_cast<DWORD>(*pid)) : nullptr;
    const bool tracked = child && child_job_ && AssignProcessToJobObject(child_job_, child);
    if (child) CloseHandle(child);
    if (tracked) result->Success();
    else result->Error("child_process", "Khong quan ly duoc ket noi Internet.");
  });
  flutter::MethodChannel<flutter::EncodableValue> file_channel(
      flutter_controller_->engine()->messenger(), "fap_helper/files",
      &flutter::StandardMethodCodec::GetInstance());
  file_channel.SetMethodCallHandler(
      [this](const auto& call, auto result) {
        const bool saving_csv = call.method_name() == "saveCsv";
        if (call.method_name() != "pickExcel" && !saving_csv) {
          result->NotImplemented();
          return;
        }
        wchar_t path[32768] = {};
        if (saving_csv && call.arguments() != nullptr) {
          const auto* name = std::get_if<std::string>(call.arguments());
          if (name != nullptr) {
            MultiByteToWideChar(CP_UTF8, 0, name->c_str(), -1, path,
                                static_cast<int>(std::size(path)));
          }
        }
        OPENFILENAMEW dialog = {};
        dialog.lStructSize = static_cast<DWORD>(sizeof(dialog));
        dialog.hwndOwner = GetHandle();
        dialog.lpstrFilter = saving_csv ? L"Attendance CSV (*.csv)\0*.csv\0\0"
                                       : L"Excel Workbook (*.xlsx)\0*.xlsx\0\0";
        dialog.lpstrFile = path;
        dialog.nMaxFile = static_cast<DWORD>(std::size(path));
        dialog.lpstrTitle = saving_csv ? L"Luu CSV diem danh FA26" : L"Chon file Excel hoc ky FA26";
        dialog.lpstrDefExt = saving_csv ? L"csv" : L"xlsx";
        dialog.Flags = OFN_PATHMUSTEXIST | OFN_NOCHANGEDIR |
                       (saving_csv ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
        if (saving_csv ? GetSaveFileNameW(&dialog) : GetOpenFileNameW(&dialog)) {
          const int length = WideCharToMultiByte(CP_UTF8, 0, path, -1,
                                                nullptr, 0, nullptr, nullptr);
          std::string utf8(static_cast<size_t>(length), '\0');
          WideCharToMultiByte(CP_UTF8, 0, path, -1, utf8.data(), length,
                              nullptr, nullptr);
          utf8.pop_back();
          result->Success(flutter::EncodableValue(utf8));
        } else if (CommDlgExtendedError() != 0) {
          result->Error("file_dialog", "Khong mo duoc hop thoai chon file.");
        } else {
          result->Success();
        }
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
  if (child_job_) { CloseHandle(child_job_); child_job_ = nullptr; }
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
