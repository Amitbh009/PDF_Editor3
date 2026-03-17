#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Returns the UTF-8 encoded arguments as a vector of std::strings.
std::vector<std::string> GetCommandLineArguments();

// Converts a UTF-16 encoded string to a UTF-8 encoded string.
std::string Utf8FromUtf16(const wchar_t* utf16_string);

#endif  // RUNNER_UTILS_H_
