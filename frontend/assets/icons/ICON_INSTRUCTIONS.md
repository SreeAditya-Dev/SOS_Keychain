# SafeHer App Icon Generation

## Required Icon Files

Place the following PNG files in this directory (`frontend/assets/icons/`):

1. **app_icon.png** (1024x1024 px)
   - Main app icon with full background
   - Coral/rose gradient background (#E8505B to #B23A48)
   - White shield icon with heart in center
   
2. **app_icon_foreground.png** (1024x1024 px)  
   - Foreground only (transparent background)
   - White shield icon with heart
   - Used for Android adaptive icons
   
3. **splash_logo.png** (512x512 px)
   - Logo for splash screen
   - White shield icon (transparent background)
   - Will appear on coral background

## Suggested Design

The SafeHer icon should feature:
- A shield shape representing protection
- A heart element symbolizing care/safety for women
- Clean, modern, minimal design
- Primary color: #E8505B (Coral Red)
- White (#FFFFFF) for the icon elements

## Quick Generation Options

### Option 1: Use an online tool
1. Go to https://www.canva.com or https://www.figma.com
2. Create a 1024x1024 canvas
3. Add a rounded square with gradient #E8505B -> #B23A48
4. Add a white shield icon with a heart cutout
5. Export as PNG

### Option 2: Use Flutter to generate placeholder
Run the app once and use the built-in Material icons as a temporary solution.

## After Creating Icons

Run these commands to generate all icon sizes:

```bash
cd frontend
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

This will automatically generate all required sizes for Android and iOS.
