---
name: Atenda Ai Core
colors:
  surface: '#10131c'
  surface-dim: '#10131c'
  surface-bright: '#363943'
  surface-container-lowest: '#0b0e17'
  surface-container-low: '#181b25'
  surface-container: '#1c1f29'
  surface-container-high: '#272a33'
  surface-container-highest: '#32343e'
  on-surface: '#e0e2ef'
  on-surface-variant: '#bbc9cf'
  inverse-surface: '#e0e2ef'
  inverse-on-surface: '#2d303a'
  outline: '#859399'
  outline-variant: '#3c494e'
  surface-tint: '#4cd6ff'
  primary: '#a4e6ff'
  on-primary: '#003543'
  primary-container: '#00d1ff'
  on-primary-container: '#00566a'
  inverse-primary: '#00677f'
  secondary: '#cfbdff'
  on-secondary: '#390093'
  secondary-container: '#5515c9'
  on-secondary-container: '#c2acff'
  tertiary: '#ffd4bc'
  on-tertiary: '#522300'
  tertiary-container: '#ffae7d'
  on-tertiary-container: '#813a00'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#b7eaff'
  primary-fixed-dim: '#4cd6ff'
  on-primary-fixed: '#001f28'
  on-primary-fixed-variant: '#004e60'
  secondary-fixed: '#e8ddff'
  secondary-fixed-dim: '#cfbdff'
  on-secondary-fixed: '#22005d'
  on-secondary-fixed-variant: '#530ec6'
  tertiary-fixed: '#ffdbc8'
  tertiary-fixed-dim: '#ffb68b'
  on-tertiary-fixed: '#321200'
  on-tertiary-fixed-variant: '#753400'
  background: '#10131c'
  on-background: '#e0e2ef'
  surface-variant: '#32343e'
typography:
  display-lg:
    fontFamily: Manrope
    fontSize: 48px
    fontWeight: '700'
    lineHeight: 56px
    letterSpacing: -0.02em
  display-md:
    fontFamily: Manrope
    fontSize: 36px
    fontWeight: '700'
    lineHeight: 44px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Manrope
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.01em
  headline-md:
    fontFamily: Manrope
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.01em
  body-lg:
    fontFamily: Manrope
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: 0em
  body-md:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: 0em
  label-lg:
    fontFamily: Manrope
    fontSize: 14px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: 0.02em
  label-sm:
    fontFamily: Manrope
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.04em
  headline-lg-mobile:
    fontFamily: Manrope
    fontSize: 24px
    fontWeight: '600'
    lineHeight: 32px
rounded:
  sm: 0.125rem
  DEFAULT: 0.25rem
  md: 0.375rem
  lg: 0.5rem
  xl: 0.75rem
  full: 9999px
spacing:
  base: 4px
  xs: 4px
  sm: 8px
  md: 16px
  lg: 24px
  xl: 32px
  2xl: 48px
  gutter: 20px
  margin: 24px
---

## Brand & Style
The design system embodies a "Technological Sophistication" aesthetic tailored for high-end B2B SaaS. It avoids the typical "gamer" vibrance in favor of a refined, deep-space atmosphere characterized by precision and intelligence. 

The style utilizes a **Modern-Corporate** foundation infused with **Glassmorphism** and **Tactile** depth. Visual hierarchy is established through layered surfaces, subtle noise textures that eliminate "flatness," and architectural grid lines that suggest structural integrity. The emotional response should be one of absolute reliability, cutting-edge AI capability, and calm efficiency.

**Key Visual Principles:**
- **Atmospheric Depth:** Use of radial glows (Cyan and Violet) to imply AI activity behind the UI plane.
- **Precision:** Thin 1px borders and sharp grid alignments.
- **Subtle Texture:** A 2-3% opacity grain overlay across all surfaces to provide a premium, analog feel.
- **No Mascots:** Intelligence is represented through motion and light, never literal characters or robots.

## Colors
The palette is rooted in a deep-space navy to provide maximum contrast for technological accents.

- **Background & Surface:** The core foundation uses `#07080D` for the base layer. Higher elevation surfaces use `#11141D`.
- **Primary (Tech Gradient):** A linear gradient from `#00D1FF` (Cyan) to `#007AFF` (Blue). This represents the core flow of data and connectivity.
- **Secondary (AI Logic):** `#8A5CFF` (Violet). Used exclusively for AI-driven features, automation status, and "intelligence" indicators.
- **Accent (Semantic/Critical):** `#FF7A00` (Orange). Reserved strictly for warnings, critical alerts, or "attention required" states.
- **Gradients:** Use low-opacity radial gradients of the Primary and Secondary colors in the background corners to provide "atmospheric" light.

## Typography
Manrope is the sole typeface for the design system. Its geometric yet approachable nature bridges the gap between high-tech and human-centric service.

- **Headlines:** Use SemiBold (600) or Bold (700) with slight negative letter-spacing to maintain a tight, professional look.
- **Body Text:** Use Regular (400) for standard readability. Ensure line heights are generous (150%) to prevent visual fatigue in data-heavy views.
- **Labels:** Use Medium (500) or SemiBold (600) in Uppercase for small labels (e.g., "WHATSAPP", "STATUS") to create clear structural markers.
- **Contrast:** On dark backgrounds, use `White/90%` for primary text and `White/60%` for secondary/hint text.

## Layout & Spacing
The design system utilizes a **12-column fluid grid** for desktop and a **4-column fluid grid** for mobile.

- **Structural Grid Lines:** In dashboards (Visão Geral), use very faint 1px lines (`#252B3A`) to define the layout grid, mimicking a technical blueprint.
- **Rhythm:** An 8px base unit drives all spacing.
- **Navigation:** A fixed left-hand sidebar (260px) houses the primary navigation (Conversas, Automações, etc.). 
- **Adaptation:** On tablets, the sidebar collapses to icons only. On mobile, the sidebar moves to a bottom navigation bar or a hamburger menu, prioritizing the "Conversas" view.

## Elevation & Depth
Depth is created through **Tonal Layering** and **Glassmorphism**, rather than traditional heavy shadows.

- **Level 0 (Background):** `#07080D` - The canvas.
- **Level 1 (Surface):** `#11141D` - Cards, Sidebar, Header. Features a 1px border (`#252B3A`).
- **Level 2 (Floating):** `#1B202D` - Modals, Popovers, Tooltips. These utilize a `16px` backdrop blur and a slight "Inner Glow" (White at 5% opacity) on the top edge to simulate light catching a glass edge.
- **Shadows:** Use a single "Ambient Shadow": `0 8px 32px rgba(0, 0, 0, 0.5)`. Do not use colored shadows unless it is a glowing AI element (using the Violet palette).

## Shapes
The shape language is **"Soft-Tech."** Rounded corners are used to keep the UI approachable, but they are kept small to maintain a sense of professional precision.

- **Standard Elements:** 4px (rounded-sm) for inputs and small buttons.
- **Cards & Containers:** 8px (rounded-lg) for dashboard modules.
- **Interactive States:** Use a subtle "Squircle" or pill-shape for active tags/chips in the "Equipe" or "WhatsApp" status indicators.

## Components
- **Buttons:** 
  - *Primary:* Gradient (Cyan to Blue), white text, 4px radius. 
  - *Secondary (AI):* Solid `#8A5CFF` or Violet-bordered with a 5% Violet fill.
  - *Ghost:* No fill, 1px border `#252B3A`, white text.
- **Inputs:** Darker than the surface (`#07080D`), 1px border. Focus state should use a Cyan glow.
- **Cards:** Surface color `#11141D`, 1px border, 8px radius. Use for "Visão Geral" widgets.
- **Chat Bubbles (Conversas):** 
  - *User:* Surface-variant (`#1B202D`) with white text.
  - *Atendente/AI:* Dark Blue gradient background with white text.
- **Status Indicators:** 
  - *WhatsApp Connected:* Primary Cyan dot with pulse animation.
  - *Critical Error:* Laranja (Orange) text and icon.
- **Navigation Items:** Active state uses a vertical Cyan line on the left and a subtle `White/5%` background highlight.