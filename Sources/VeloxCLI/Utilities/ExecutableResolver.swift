import Foundation

func resolveExecutable(_ name: String) -> String? {
  let env = ProcessInfo.processInfo.environment

#if os(Windows)
  let pathSeparator: Character = ";"
  let extensions = (env["PATHEXT"] ?? ".EXE;.CMD;.BAT")
    .split(separator: ";")
    .map { String($0).lowercased() }
#else
  let pathSeparator: Character = ":"
  let extensions = [""]
#endif

  let paths = env["PATH"]?.split(separator: pathSeparator).map(String.init) ?? []

  for dir in paths {
    for ext in extensions {
      let candidate = URL(fileURLWithPath: dir)
        .appendingPathComponent(name + ext).path
      if FileManager.default.fileExists(atPath: candidate) {
        return candidate
      }
    }
  }
  return nil
}
