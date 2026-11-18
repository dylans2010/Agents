#ifndef COINCIDE_MACOS_FFI_H
#define COINCIDE_MACOS_FFI_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct CoincideMacOSRuntime CoincideMacOSRuntime;

void coincide_macos_adopt_login_path(void);
bool coincide_macos_handoff_if_running(const char *nullable_data_dir);
CoincideMacOSRuntime *coincide_macos_open(
    const char *nullable_data_dir,
    const char *app_version,
    char **out_error
);
char *coincide_macos_poll_status(CoincideMacOSRuntime *runtime);
char *coincide_macos_adapter_call(CoincideMacOSRuntime *runtime, const char *request_json);
char *coincide_macos_desktop_call(CoincideMacOSRuntime *runtime, const char *action_json);
void coincide_macos_close(CoincideMacOSRuntime *runtime);
void coincide_macos_string_free(char *ptr);

#ifdef __cplusplus
}
#endif

#endif
