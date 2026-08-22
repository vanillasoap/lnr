# lnr

Your Linear issues in the macOS menubar. Lightweight, native, and stays out of your way.

## Build from Source

Requires macOS 14 (Sonoma) and Xcode 15+.

```bash
# Clone and build
git clone https://github.com/vanillasoap/lnr.git
cd lnr
swift build

# Or open in Xcode
open Package.swift
```

### Configure as Agent App (No Dock Icon)

After opening in Xcode, set the Info.plist path in Build Settings:
- Build Settings → Packaging → Info.plist File → `Sources/lnr/Info.plist`

Then build and run from Xcode (⌘R).

## Setup

1. Get a Linear personal API key from [linear.app/settings/api](https://linear.app/settings/api)
2. Launch lnr, click the ⊙ icon in your menubar
3. Paste your API key and pick your teams
4. Done, your issues appear in the menubar

## License

MIT
