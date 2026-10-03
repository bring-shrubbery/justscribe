# DynamicNotchKit (vendored)

Copied from https://github.com/MrKai77/DynamicNotchKit at 1.0.0 (3c40593), MIT licence (see LICENSE).
Vendored so the overlay can differ from upstream in two ways:

- `Views/NotchContentView.swift`: no drop shadow around the expanded notch.
- `Views/NotchView.swift`: the expanded content grows down from the top edge instead of scaling around its centre.

Everything else is unchanged. The Swift package reference in the Xcode project is no longer imported;
remove it in Xcode (Package Dependencies) when convenient — it is harmless until then.
