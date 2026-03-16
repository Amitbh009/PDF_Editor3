#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

// Returns the UTF-8 encoded arguments as a vector of std::strings.
std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
