# Versioning

Always increment the app version with each update pushed or merged to `main`.
Use a patch bump unless the user specifies otherwise. Update both
`CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`,
keeping them identical. Local builds and CI use this recorded version.
