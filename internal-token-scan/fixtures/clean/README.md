# Fixture: a tree that must pass the scan

Ordinary published text. It explains what things mean instead of naming records only the
authors can open: a fix for a crash when a root path is given without a trailing separator, a
note that credentials are read from the environment, a mention of version 0.9.0 and of
`Directory.Build.props`, and a URL such as https://example.org/docs -- none of which is a token
the scan reports.

Things that look like a drive path but are not one: `file:///tmp/x`, `key:/v`, a scheme such as
`https://example.com/x`, and the system roots a Windows runner always has, `C:\Program Files\LLVM\bin`,
`C:\Program Files (x86)\Windows Kits\10`, `C:/Program Files/Git/bin` and `C:\Windows\System32`.
