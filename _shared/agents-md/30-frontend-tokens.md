## Frontend Design — Token Requirements

For ALL frontend design implementations (when using any UI-building skill or building any UI):

1. **Check for design system tokens first.** Before hardcoding any color, spacing, typography, elevation, or motion value, look for the corresponding design system token from whatever system is in use in this project.
2. **Match tokens to spec.** Ensure the underlying token values match exactly what is specified in the Figma designs or provided in the prompt. Do not approximate or substitute a visually similar token.
3. **Use tokens, not raw values.** Reference CSS custom properties or JS/TS token constants rather than hardcoded hex, px, or rem values wherever a token exists.
4. **Flag missing tokens.** If a Figma spec references a token that doesn't exist in the token set, surface that gap explicitly rather than silently falling back to a raw value.
