# XPulse

**Author:** Ixis

**Dependencies:** LibAddonMenu-2.0

## AI assistance disclaimer

This project was developed with assistance from AI tools. AI-generated suggestions were reviewed and adapted by the author, but users should verify behavior and report issues through the project repository. The author remains responsible for the final implementation.

XPulse lets you move and resize the native ESO experience bar without changing the action bar layout.

## Commands

- `/xpulse move` toggles a highlighted drag mode for the experience bar.
- `/xpulse scale 80` resizes the bar to 80%. Values from 50% to 200% are supported.
- `/xpulse reset last` restores the previous position and scale.
- `/xpulse reset original` restores the original game position and size.
- `/xpulse reset` remains an alias for `/xpulse reset original`.

XPulse also adds an **XPulse** panel under **Settings > Addons**. It contains the move toggle, scale slider, and both reset buttons. XPulse stores its position, scale, original game defaults, and up to 10 previous position/scale states account-wide. Reload the user interface after installing the addon, then enable moving from the settings panel or use `/xpulse move` to position the bar.
