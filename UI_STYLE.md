# UI Style

## Direction

The app should feel like a compact Marvel Rivals hero-select HUD: bold comic typography, angled panels, high-contrast yellow actions, charcoal interface surfaces, and role-coded roster rows.

## Visual Rules

- Use black, charcoal, yellow, red, cyan, and green as the core palette.
- Use yellow for primary actions, selected tabs, vote counts, and important highlights.
- Use angled `clip-path` panels for HUD blocks and buttons.
- Use halftone dots and diagonal line texture as surface treatment.
- Keep panels dense and utilitarian; this is an app surface, not a marketing page.
- Keep card corners at 6px or less unless an element is clipped into an angled shape.
- Role colors:
  - Vanguard: cyan
  - Duelist: red
  - Strategist: green

## Typography

- Main headings use condensed, heavy comic/game typography.
- Supporting copy and form controls use a readable sans-serif.
- Text is uppercase for controls, labels, and hero names.
- Do not use negative letter spacing.

## Layout

- Desktop uses a two-column layout: category manager and ranked voting stage.
- The start screen shows category buttons; selecting one opens the ranked roster.
- The voting stage shows a draggable ranked list for the current category.
- Category management includes role preset buttons and a compact hero icon grid for eligible hero selection.
- Mobile stacks all panels vertically.
- Ranked rows should stay scan-friendly, with rank first, portrait second, role/name third, controls last.
